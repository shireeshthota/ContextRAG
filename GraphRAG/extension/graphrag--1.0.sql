-- =============================================================================
-- GraphRAG Extension v1.0
-- Graph-enhanced Retrieval Augmented Generation using Apache AGE
-- =============================================================================
--
-- This extension provides graph-based RAG capabilities on top of PostgreSQL:
-- - Property graph storage via Apache AGE
-- - Vector similarity search via pgvector
-- - Graph traversal and expansion for enhanced context
-- - Subgraph extraction for LLM consumption
--
-- Prerequisites:
-- - PostgreSQL 14+
-- - Apache AGE extension
-- - pgvector extension
--
-- Usage:
--   CREATE EXTENSION graphrag;
--   SELECT graphrag.ensure_age_loaded();
--   SELECT create_graph('support_graph');
-- =============================================================================

-- Ensure dependencies are installed
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS vector;

-- Create schema
CREATE SCHEMA IF NOT EXISTS graphrag;

COMMENT ON SCHEMA graphrag IS 'GraphRAG: Graph-enhanced Retrieval Augmented Generation using Apache AGE';

-- =============================================================================
-- CORE TABLES
-- =============================================================================

-- Node Embeddings: Vector embeddings for graph nodes
CREATE TABLE graphrag.node_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_label TEXT NOT NULL,
    source_id TEXT NOT NULL,
    embedding_type TEXT NOT NULL,       -- 'base' or 'neighborhood'
    embedding vector(1536) NOT NULL,
    embedded_text TEXT,
    model_name TEXT DEFAULT 'text-embedding-3-small',
    content_hash TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (node_label, source_id, embedding_type)
);

COMMENT ON TABLE graphrag.node_embeddings IS
'Vector embeddings for graph nodes. Supports base and neighborhood embeddings.';

-- Subgraph Cache: Cached subgraph extractions
CREATE TABLE graphrag.subgraph_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_label TEXT NOT NULL,
    source_id TEXT NOT NULL,
    max_hops INT NOT NULL DEFAULT 2,
    max_nodes INT NOT NULL DEFAULT 20,
    subgraph_text TEXT NOT NULL,
    subgraph_json JSONB,
    node_count INT,
    edge_count INT,
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    is_valid BOOLEAN DEFAULT TRUE,
    UNIQUE (node_label, source_id, max_hops, max_nodes)
);

COMMENT ON TABLE graphrag.subgraph_cache IS
'Cached subgraph extractions for LLM context.';

-- Node ID Map: Maps source IDs to AGE internal IDs
CREATE TABLE graphrag.node_id_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_label TEXT NOT NULL,
    source_id TEXT NOT NULL,
    age_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (node_label, source_id),
    UNIQUE (age_id)
);

-- Graph Statistics
CREATE TABLE graphrag.graph_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stat_type TEXT NOT NULL,
    stat_key TEXT,
    stat_value NUMERIC,
    stat_json JSONB,
    computed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Search History (optional)
CREATE TABLE graphrag.search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_text TEXT,
    query_embedding vector(1536),
    search_type TEXT,
    params JSONB,
    result_count INT,
    top_result_id TEXT,
    top_result_score REAL,
    execution_time_ms INT,
    searched_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- HNSW indexes for vector search (separate by embedding type)
CREATE INDEX idx_node_embeddings_base_hnsw
ON graphrag.node_embeddings USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
WHERE embedding_type = 'base';

CREATE INDEX idx_node_embeddings_neighborhood_hnsw
ON graphrag.node_embeddings USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
WHERE embedding_type = 'neighborhood';

-- B-tree indexes for lookups
CREATE INDEX idx_node_embeddings_node_lookup
ON graphrag.node_embeddings (node_label, source_id);

CREATE INDEX idx_node_embeddings_type
ON graphrag.node_embeddings (embedding_type);

CREATE INDEX idx_subgraph_cache_lookup
ON graphrag.subgraph_cache (node_label, source_id, max_hops, max_nodes)
WHERE is_valid = TRUE;

CREATE INDEX idx_node_id_map_age_id
ON graphrag.node_id_map (age_id);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Ensure AGE is loaded for the session
CREATE OR REPLACE FUNCTION graphrag.ensure_age_loaded()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    LOAD 'age';
    SET search_path = ag_catalog, graphrag, "$user", public;
END;
$$;

-- =============================================================================
-- GRAPH TRAVERSAL FUNCTIONS
-- =============================================================================

-- Get 1-hop neighbors
CREATE OR REPLACE FUNCTION graphrag.get_node_neighborhood(
    p_node_label TEXT,
    p_source_id TEXT,
    p_edge_types TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    neighbor_label TEXT,
    neighbor_source_id TEXT,
    neighbor_properties JSONB,
    edge_type TEXT,
    edge_direction TEXT,
    edge_properties JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_edge_filter TEXT := '';
BEGIN
    IF p_edge_types IS NOT NULL AND array_length(p_edge_types, 1) > 0 THEN
        v_edge_filter := ' WHERE type(r) IN [' ||
            (SELECT string_agg('''' || unnest || '''', ', ') FROM unnest(p_edge_types)) || ']';
    END IF;

    -- Outgoing edges
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})-[r]->(m)
        %s
        RETURN labels(m)[0], m.source_id, properties(m), type(r), 'outgoing', properties(r)
    $cypher$, p_node_label, p_source_id, v_edge_filter))
    AS (nl agtype, nsi agtype, np agtype, et agtype, ed agtype, ep agtype);

    -- Incoming edges
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})<-[r]-(m)
        %s
        RETURN labels(m)[0], m.source_id, properties(m), type(r), 'incoming', properties(r)
    $cypher$, p_node_label, p_source_id, v_edge_filter))
    AS (nl agtype, nsi agtype, np agtype, et agtype, ed agtype, ep agtype);
END;
$$;

-- Get extended multi-hop context
CREATE OR REPLACE FUNCTION graphrag.get_extended_context(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 2,
    p_max_nodes INT DEFAULT 50
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    properties JSONB,
    path_length INT,
    path_description TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Starting node
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})
        RETURN labels(n)[0], n.source_id, properties(n), 0, 'origin'
    $cypher$, p_node_label, p_source_id))
    AS (nl agtype, si agtype, p agtype, pl agtype, pd agtype);

    -- 1-hop
    IF p_max_hops >= 1 THEN
        RETURN QUERY
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I {source_id: %L})-[r]-(m)
            RETURN DISTINCT labels(m)[0], m.source_id, properties(m), 1,
                   labels(n)[0] || ' -[' || type(r) || ']- ' || labels(m)[0]
            LIMIT %s
        $cypher$, p_node_label, p_source_id, p_max_nodes))
        AS (nl agtype, si agtype, p agtype, pl agtype, pd agtype);
    END IF;

    -- 2-hop
    IF p_max_hops >= 2 THEN
        RETURN QUERY
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I {source_id: %L})-[r1]-(m1)-[r2]-(m2)
            WHERE n <> m2 AND m1 <> m2
            RETURN DISTINCT labels(m2)[0], m2.source_id, properties(m2), 2,
                   labels(n)[0] || ' -> ' || labels(m1)[0] || ' -> ' || labels(m2)[0]
            LIMIT %s
        $cypher$, p_node_label, p_source_id, p_max_nodes))
        AS (nl agtype, si agtype, p agtype, pl agtype, pd agtype);
    END IF;
END;
$$;

-- Build graph context as text
CREATE OR REPLACE FUNCTION graphrag.build_graph_context_text(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 1
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_result TEXT := '';
    rec RECORD;
BEGIN
    SELECT * INTO rec FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})
        RETURN properties(n)
    $cypher$, p_node_label, p_source_id))
    AS (props agtype);

    IF rec IS NOT NULL THEN
        v_result := p_node_label || ': ' || rec.props::TEXT || E'\n\nRelationships:\n';
    END IF;

    FOR rec IN SELECT * FROM graphrag.get_node_neighborhood(p_node_label, p_source_id)
    LOOP
        IF rec.edge_direction = 'outgoing' THEN
            v_result := v_result || '  -[' || rec.edge_type || ']-> ' ||
                       rec.neighbor_label || ' (' || rec.neighbor_source_id || ')' || E'\n';
        ELSE
            v_result := v_result || '  <-[' || rec.edge_type || ']- ' ||
                       rec.neighbor_label || ' (' || rec.neighbor_source_id || ')' || E'\n';
        END IF;
    END LOOP;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- STRUCTURAL SIMILARITY
-- =============================================================================

CREATE OR REPLACE FUNCTION graphrag.find_structurally_similar(
    p_node_label TEXT,
    p_source_id TEXT,
    p_search_label TEXT DEFAULT NULL,
    p_min_shared INT DEFAULT 1,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    similar_source_id TEXT,
    shared_neighbors INT,
    shared_neighbor_details JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_search_label TEXT;
BEGIN
    v_search_label := COALESCE(p_search_label, p_node_label);

    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})-[]-(shared)-[]-(similar:%I)
        WHERE n <> similar
        WITH similar, collect(DISTINCT shared) as shared_nodes
        WHERE size(shared_nodes) >= %s
        RETURN similar.source_id, size(shared_nodes),
               [s IN shared_nodes | {label: labels(s)[0], id: s.source_id}]
        ORDER BY size(shared_nodes) DESC
        LIMIT %s
    $cypher$, p_node_label, p_source_id, v_search_label, p_min_shared, p_limit))
    AS (ssi agtype, sn agtype, snd agtype);
END;
$$;

-- =============================================================================
-- VECTOR SEARCH FUNCTIONS
-- =============================================================================

-- Basic vector search
CREATE OR REPLACE FUNCTION graphrag.vector_search(
    p_query_embedding vector(1536),
    p_node_label TEXT DEFAULT NULL,
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_min_similarity REAL DEFAULT 0.0
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    similarity REAL,
    embedded_text TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_node_label IS NULL THEN
        RETURN QUERY
        SELECT e.node_label, e.source_id,
               (1 - (e.embedding <=> p_query_embedding))::REAL,
               e.embedded_text
        FROM graphrag.node_embeddings e
        WHERE e.embedding_type = p_embedding_type
          AND (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
        ORDER BY e.embedding <=> p_query_embedding
        LIMIT p_limit;
    ELSE
        RETURN QUERY
        SELECT e.node_label, e.source_id,
               (1 - (e.embedding <=> p_query_embedding))::REAL,
               e.embedded_text
        FROM graphrag.node_embeddings e
        WHERE e.embedding_type = p_embedding_type
          AND e.node_label = p_node_label
          AND (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
        ORDER BY e.embedding <=> p_query_embedding
        LIMIT p_limit;
    END IF;
END;
$$;

-- Graph-enhanced search (vector + connectivity)
CREATE OR REPLACE FUNCTION graphrag.graph_enhanced_search(
    p_query_embedding vector(1536),
    p_node_label TEXT DEFAULT NULL,
    p_limit INT DEFAULT 10,
    p_expansion_hops INT DEFAULT 1,
    p_embedding_type TEXT DEFAULT 'base'
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    similarity REAL,
    neighbor_count INT,
    combined_score REAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH vector_results AS (
        SELECT v.node_label, v.source_id, v.similarity
        FROM graphrag.vector_search(p_query_embedding, p_node_label, p_embedding_type, p_limit * 3, 0.0) v
    ),
    with_neighbors AS (
        SELECT vr.node_label, vr.source_id, vr.similarity,
               (SELECT COUNT(*)::INT FROM graphrag.get_node_neighborhood(vr.node_label, vr.source_id))
        FROM vector_results vr
    )
    SELECT wn.node_label, wn.source_id, wn.similarity, wn.count,
           (wn.similarity + (LEAST(wn.count, 10) * 0.01))::REAL
    FROM with_neighbors wn
    ORDER BY (wn.similarity + (LEAST(wn.count, 10) * 0.01)) DESC
    LIMIT p_limit;
END;
$$;

-- Hybrid search (vector + property filters)
CREATE OR REPLACE FUNCTION graphrag.hybrid_search(
    p_query_embedding vector(1536),
    p_node_label TEXT,
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_property_filter JSONB DEFAULT NULL,
    p_min_similarity REAL DEFAULT 0.0
)
RETURNS TABLE (
    source_id TEXT,
    similarity REAL,
    properties JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cypher_where TEXT := '';
    v_filter_key TEXT;
    v_filter_value TEXT;
BEGIN
    IF p_property_filter IS NOT NULL THEN
        FOR v_filter_key, v_filter_value IN SELECT * FROM jsonb_each_text(p_property_filter)
        LOOP
            IF v_cypher_where = '' THEN
                v_cypher_where := format('WHERE n.%I = %L', v_filter_key, v_filter_value);
            ELSE
                v_cypher_where := v_cypher_where || format(' AND n.%I = %L', v_filter_key, v_filter_value);
            END IF;
        END LOOP;
    END IF;

    RETURN QUERY
    WITH filtered_nodes AS (
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I) %s
            RETURN n.source_id, properties(n)
        $cypher$, p_node_label, v_cypher_where))
        AS (source_id agtype, properties agtype)
    )
    SELECT fn.source_id::TEXT,
           (1 - (e.embedding <=> p_query_embedding))::REAL,
           fn.properties::JSONB
    FROM filtered_nodes fn
    JOIN graphrag.node_embeddings e
        ON e.node_label = p_node_label
        AND e.source_id = fn.source_id::TEXT
        AND e.embedding_type = p_embedding_type
    WHERE (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
    ORDER BY e.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$;

-- =============================================================================
-- LLM CONTEXT FUNCTIONS
-- =============================================================================

-- Extract subgraph for LLM context
CREATE OR REPLACE FUNCTION graphrag.extract_subgraph_for_llm(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 2,
    p_max_nodes INT DEFAULT 20,
    p_use_cache BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_result TEXT := '';
    v_cached_text TEXT;
    rec RECORD;
    v_node_count INT := 0;
    v_current_label TEXT := '';
BEGIN
    -- Check cache
    IF p_use_cache THEN
        SELECT subgraph_text INTO v_cached_text
        FROM graphrag.subgraph_cache
        WHERE node_label = p_node_label AND source_id = p_source_id
          AND max_hops = p_max_hops AND max_nodes = p_max_nodes
          AND is_valid = TRUE
          AND (expires_at IS NULL OR expires_at > NOW());

        IF v_cached_text IS NOT NULL THEN
            RETURN v_cached_text;
        END IF;
    END IF;

    -- Build subgraph text
    v_result := '=== SUBGRAPH CONTEXT ===' || E'\n\n';

    FOR rec IN
        SELECT * FROM graphrag.get_extended_context(p_node_label, p_source_id, p_max_hops, p_max_nodes)
        ORDER BY path_length, node_label
    LOOP
        IF rec.path_length::INT = 0 THEN
            v_result := v_result || '## Primary Entity' || E'\n';
        ELSIF v_current_label <> rec.path_length::TEXT THEN
            v_result := v_result || E'\n## ' || rec.path_length::TEXT || '-hop Neighbors' || E'\n';
            v_current_label := rec.path_length::TEXT;
        END IF;

        v_result := v_result || '- ' || rec.node_label || ' (' || rec.source_id || '): ';
        v_result := v_result || rec.properties::TEXT || E'\n';

        IF rec.path_length::INT > 0 THEN
            v_result := v_result || '  Path: ' || rec.path_description || E'\n';
        END IF;

        v_node_count := v_node_count + 1;
        IF v_node_count >= p_max_nodes THEN
            v_result := v_result || E'\n... (truncated at ' || p_max_nodes || ' nodes)';
            EXIT;
        END IF;
    END LOOP;

    -- Cache result
    IF p_use_cache THEN
        INSERT INTO graphrag.subgraph_cache (node_label, source_id, max_hops, max_nodes, subgraph_text, node_count)
        VALUES (p_node_label, p_source_id, p_max_hops, p_max_nodes, v_result, v_node_count)
        ON CONFLICT (node_label, source_id, max_hops, max_nodes)
        DO UPDATE SET subgraph_text = EXCLUDED.subgraph_text, node_count = EXCLUDED.node_count,
                      computed_at = NOW(), is_valid = TRUE;
    END IF;

    RETURN v_result;
END;
$$;

-- Path-based similarity search with explanations
CREATE OR REPLACE FUNCTION graphrag.path_similarity_search(
    p_query_embedding vector(1536),
    p_target_label TEXT,
    p_context_label TEXT,
    p_context_source_id TEXT,
    p_limit INT DEFAULT 5,
    p_embedding_type TEXT DEFAULT 'base'
)
RETURNS TABLE (
    target_source_id TEXT,
    similarity REAL,
    path_to_context TEXT,
    relevance_explanation TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH semantic_matches AS (
        SELECT v.source_id, v.similarity
        FROM graphrag.vector_search(p_query_embedding, p_target_label, p_embedding_type, p_limit * 5, 0.3) v
    ),
    path_connections AS (
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (ctx:%I {source_id: %L})-[*1..3]-(target:%I)
            WITH target, min(length(shortestPath((ctx)-[*]-(target)))) as dist
            RETURN target.source_id, dist
        $cypher$, p_context_label, p_context_source_id, p_target_label))
        AS (target_id agtype, dist agtype)
    )
    SELECT sm.source_id,
           sm.similarity,
           CASE WHEN pc.dist IS NOT NULL
                THEN p_context_label || ' -> ' || pc.dist::TEXT || ' hops -> ' || p_target_label
                ELSE 'No direct path' END,
           CASE WHEN pc.dist IS NOT NULL AND pc.dist::INT = 1 THEN 'Directly connected - highly relevant'
                WHEN pc.dist IS NOT NULL AND pc.dist::INT = 2 THEN 'Connected via shared entity'
                WHEN pc.dist IS NOT NULL THEN 'Indirectly connected'
                ELSE 'Found via semantic similarity only' END
    FROM semantic_matches sm
    LEFT JOIN path_connections pc ON pc.target_id::TEXT = sm.source_id
    ORDER BY CASE WHEN pc.dist IS NOT NULL THEN 0 ELSE 1 END,
             pc.dist::INT NULLS LAST,
             sm.similarity DESC
    LIMIT p_limit;
END;
$$;

-- =============================================================================
-- EMBEDDING MANAGEMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION graphrag.store_node_embedding(
    p_node_label TEXT,
    p_source_id TEXT,
    p_embedding_type TEXT,
    p_embedding vector(1536),
    p_embedded_text TEXT DEFAULT NULL,
    p_model_name TEXT DEFAULT 'text-embedding-3-small'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO graphrag.node_embeddings (
        node_label, source_id, embedding_type, embedding,
        embedded_text, model_name, content_hash
    )
    VALUES (
        p_node_label, p_source_id, p_embedding_type, p_embedding,
        p_embedded_text, p_model_name, md5(COALESCE(p_embedded_text, ''))
    )
    ON CONFLICT (node_label, source_id, embedding_type)
    DO UPDATE SET
        embedding = EXCLUDED.embedding,
        embedded_text = EXCLUDED.embedded_text,
        content_hash = EXCLUDED.content_hash,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- =============================================================================
-- CACHE MANAGEMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION graphrag.invalidate_subgraph_cache(
    p_node_label TEXT DEFAULT NULL,
    p_source_id TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    IF p_node_label IS NOT NULL AND p_source_id IS NOT NULL THEN
        UPDATE graphrag.subgraph_cache SET is_valid = FALSE
        WHERE node_label = p_node_label AND source_id = p_source_id;
    ELSIF p_node_label IS NOT NULL THEN
        UPDATE graphrag.subgraph_cache SET is_valid = FALSE
        WHERE node_label = p_node_label;
    ELSE
        UPDATE graphrag.subgraph_cache SET is_valid = FALSE;
    END IF;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION graphrag.cleanup_expired_cache()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    DELETE FROM graphrag.subgraph_cache
    WHERE (expires_at IS NOT NULL AND expires_at < NOW()) OR is_valid = FALSE;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- =============================================================================
-- STATISTICS
-- =============================================================================

CREATE OR REPLACE FUNCTION graphrag.get_graph_stats()
RETURNS TABLE (stat_name TEXT, stat_value BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY SELECT 'nodes_total'::TEXT, COUNT(*)::BIGINT
    FROM ag_catalog.cypher('support_graph', $$ MATCH (n) RETURN n $$) AS (n agtype);

    RETURN QUERY SELECT 'edges_total'::TEXT, COUNT(*)::BIGINT
    FROM ag_catalog.cypher('support_graph', $$ MATCH ()-[r]->() RETURN r $$) AS (r agtype);

    RETURN QUERY SELECT 'embeddings_base'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.node_embeddings WHERE embedding_type = 'base';

    RETURN QUERY SELECT 'embeddings_neighborhood'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.node_embeddings WHERE embedding_type = 'neighborhood';

    RETURN QUERY SELECT 'cache_entries_valid'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.subgraph_cache WHERE is_valid = TRUE;
END;
$$;
