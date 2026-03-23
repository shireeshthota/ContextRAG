-- ContextRAG Test Queries
-- Run with: psql -d contextrag_test -f test_project/queries/search_examples.sql

-- =============================================================================
-- PART 1: PRE-EMBEDDING TESTS (run these right after setup_test_db.sh)
-- =============================================================================

\echo '=== TEST 1: Verify entity counts ==='
SELECT entity_type, COUNT(*) AS count
FROM contextrag.entities
GROUP BY entity_type
ORDER BY entity_type;

\echo '=== TEST 2: Verify context was attached to entities ==='
SELECT
    e.entity_type,
    e.source_id,
    COUNT(ec.id) AS context_count
FROM contextrag.entities e
JOIN contextrag.entity_context ec ON ec.entity_id = e.id
GROUP BY e.entity_type, e.source_id
ORDER BY e.entity_type, e.source_id::int;

\echo '=== TEST 3: Check context types and weights ==='
SELECT
    context_type,
    COUNT(*) AS count,
    ROUND(AVG(weight)::numeric, 2) AS avg_weight,
    ROUND(MIN(weight)::numeric, 2) AS min_weight,
    ROUND(MAX(weight)::numeric, 2) AS max_weight
FROM contextrag.entity_context
GROUP BY context_type
ORDER BY count DESC;

\echo '=== TEST 4: Verify build_context_text produces output ==='
SELECT
    e.entity_type,
    e.source_id,
    contextrag.build_context_text(e.id) AS context_text
FROM contextrag.entities e
ORDER BY e.entity_type, e.source_id::int
LIMIT 3;

\echo '=== TEST 5: Verify build_full_text combines content + context ==='
SELECT
    e.entity_type,
    e.source_id,
    LEFT(contextrag.build_full_text(e.id), 200) AS full_text_preview
FROM contextrag.entities e
ORDER BY e.entity_type, e.source_id::int
LIMIT 3;

\echo '=== TEST 6: Verify entity details function ==='
SELECT
    entity_type,
    source_table,
    source_id,
    jsonb_array_length(contexts) AS context_count,
    embedding_types
FROM contextrag.get_entity_details(
    (SELECT id FROM contextrag.entities WHERE source_table = 'tickets' AND source_id = '1')
);

\echo '=== TEST 7: All entities should be unembedded at this point ==='
SELECT
    entity_type,
    source_id,
    LEFT(full_text, 80) AS text_preview
FROM contextrag.get_unembedded_entities('base', NULL, 100);

\echo '=== TEST 8: All entities should be stale (no embeddings yet) ==='
SELECT
    entity_type,
    source_id,
    entity_updated_at,
    embedding_created_at
FROM contextrag.get_stale_entities('base', 100);

\echo '=== TEST 9: Context filtering - find urgent tickets ==='
SELECT
    e.entity_type,
    e.source_id,
    e.base_content->>'subject' AS subject,
    ec.context_value AS priority
FROM contextrag.entities e
JOIN contextrag.entity_context ec ON ec.entity_id = e.id
WHERE ec.context_type = 'priority'
  AND ec.context_value = 'urgent';

\echo '=== TEST 10: Context filtering - find enterprise customers ==='
SELECT
    e.source_id,
    e.base_content->>'subject' AS subject,
    ec.context_value AS plan_type
FROM contextrag.entities e
JOIN contextrag.entity_context ec ON ec.entity_id = e.id
WHERE ec.context_key = 'plan_type'
  AND ec.context_value = 'enterprise';

\echo '=== TEST 11: Deactivate and reactivate an entity ==='
SELECT contextrag.deactivate_entity(
    (SELECT id FROM contextrag.entities WHERE source_table = 'tickets' AND source_id = '1')
);
-- Should show 0 active for ticket 1
SELECT source_id, is_active FROM contextrag.entities WHERE source_table = 'tickets' AND source_id = '1';
-- Reactivate
SELECT contextrag.reactivate_entity(
    (SELECT id FROM contextrag.entities WHERE source_table = 'tickets' AND source_id = '1')
);
SELECT source_id, is_active FROM contextrag.entities WHERE source_table = 'tickets' AND source_id = '1';

\echo '=== TEST 12: Get overall stats ==='
SELECT * FROM contextrag.get_stats();

\echo '=== PRE-EMBEDDING TESTS COMPLETE ==='

-- =============================================================================
-- PART 2: POST-EMBEDDING TESTS (run after batch_embed.py)
-- =============================================================================
-- Uncomment and run these after:
--   python batch_embed.py --embedding-type base
--   python batch_embed.py --embedding-type local_context

/*
\echo '=== TEST 13: Verify embeddings were stored ==='
SELECT
    e.entity_type,
    e.source_id,
    emb.embedding_type,
    emb.model_name,
    emb.created_at
FROM contextrag.entity_embeddings emb
JOIN contextrag.entities e ON e.id = emb.entity_id
ORDER BY e.entity_type, e.source_id::int, emb.embedding_type;

\echo '=== TEST 14: No entities should be unembedded now ==='
SELECT COUNT(*) AS unembedded_base FROM contextrag.get_unembedded_entities('base', NULL, 100);
SELECT COUNT(*) AS unembedded_context FROM contextrag.get_unembedded_entities('local_context', NULL, 100);

\echo '=== TEST 15: Vector search - use ticket 1 embedding to find similar tickets ==='
SELECT
    vs.source_id,
    vs.entity_type,
    vs.base_content->>'subject' AS subject,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.vector_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 5, NULL
) vs;

\echo '=== TEST 16: Cross-entity search - find KB articles relevant to ticket 1 ==='
SELECT
    vs.source_id,
    vs.base_content->>'title' AS title,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.vector_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 5, 'kb_article'
) vs;

\echo '=== TEST 17: Multi-embedding search - base vs context weighted ==='
SELECT
    source_id,
    entity_type,
    base_content->>'subject' AS subject,
    ROUND(base_similarity::numeric, 4) AS base_sim,
    ROUND(context_similarity::numeric, 4) AS ctx_sim,
    ROUND(combined_score::numeric, 4) AS combined
FROM contextrag.multi_embedding_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    0.7, 0.3, 10, NULL
);

\echo '=== TEST 18: Hybrid search - filter by enterprise metadata ==='
SELECT
    source_id,
    base_content->>'subject' AS subject,
    ROUND(similarity::numeric, 4) AS similarity
FROM contextrag.hybrid_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 10, 'ticket',
    '{"customer_plan": "enterprise"}'::jsonb,
    0.0
);

\echo '=== TEST 19: Context-aware search - only urgent priority ==='
SELECT
    source_id,
    base_content->>'subject' AS subject,
    ROUND(similarity::numeric, 4) AS similarity
FROM contextrag.context_aware_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 10, 'ticket',
    'priority', 'ticket_priority', 'urgent'
);

\echo '=== POST-EMBEDDING TESTS COMPLETE ==='
*/
