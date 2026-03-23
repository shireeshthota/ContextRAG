-- ContextRAG Vector Embedding Queries
-- Advanced queries combining support schema data with contextrag vector embeddings
-- Run after: batch_embed.py --embedding-type base && batch_embed.py --embedding-type local_context
--
-- DATA REFERENCE (for understanding expected results):
--
--   Tickets:
--     1: "Unable to login with SSO after password change"       | SecureAuth   | high   | technical       | enterprise (Acme Corp)       | Tom Anderson
--     2: "Question about upgrading from Pro to Enterprise"      | CloudSync    | medium | billing         | pro (TechStart)              | Jane Martinez
--     3: "Request: Add folder-level sharing permissions"        | DataVault    | low    | feature_request | enterprise (Global Retail)   | (unassigned)
--     4: "Files not syncing - data loss concern"                | CloudSync    | urgent | bug             | pro (Innovate Co)            | Tom Anderson
--     5: "API rate limit exceeded unexpectedly"                 | API Gateway  | high   | technical       | enterprise (Big Bank)        | Sam Williams
--     6: "Password reset email not received"                    | SecureAuth   | medium | technical       | free (David Brown)           | (unassigned)
--     7: "Double charged for monthly subscription"              | CloudSync    | medium | billing         | pro (Startup XYZ)            | Jane Martinez
--     8: "How to integrate API Gateway with our legacy system"  | API Gateway  | medium | technical       | enterprise (Healthcare Plus) | Sam Williams
--
--   KB Articles:
--     1: "How to configure SSO with Azure AD"              | how_to          | SecureAuth   | sso, azure, saml, authentication
--     2: "Troubleshooting CloudSync Pro sync issues"       | troubleshooting | CloudSync    | sync, files, desktop, troubleshooting
--     3: "Understanding API Gateway rate limits"           | how_to          | API Gateway  | api, rate-limit, throttling, best-practices
--     4: "How to reset your SecureAuth password"           | how_to          | SecureAuth   | password, reset, login, security
--     5: "Sharing files and folders in DataVault"          | how_to          | DataVault    | sharing, permissions, collaboration, security
--
--   Entity metadata (stored in contextrag.entities.metadata):
--     Tickets:     {"product": "<product_name>", "customer_plan": "<plan_type>"}
--     KB Articles: {"product": "<product_name>"}

-- =============================================================================
-- 1. FIND SIMILAR TICKETS TO A GIVEN TICKET
-- Use case: Agent gets a new ticket, wants to see past similar issues
-- =============================================================================
--
-- HOW IT WORKS:
--   Takes ticket 1's base embedding (SSO login failure on SecureAuth) and runs
--   cosine similarity against all other ticket base embeddings via vector_search().
--   Filters to entity_type='ticket' so KB articles are excluded.
--
-- EXPECTED RESULTS:
--   The query vector is about SSO authentication failure after a password change.
--   Semantically, the closest tickets should be:
--
--   1. Ticket 1 itself (similarity = 1.0000) — the query IS this ticket's embedding,
--      so it will always be the top result with perfect similarity.
--   2. Ticket 6 "Password reset email not received" — also about SecureAuth, also an
--      authentication/login issue. Both deal with users unable to access their accounts.
--      Expected similarity: high (~0.80-0.90).
--   3. Ticket 5 or 8 — both are technical issues but about API Gateway, so they share
--      the "technical support" semantic space but differ in product domain.
--      Expected similarity: moderate (~0.65-0.80).
--   4. Tickets 2, 3, 4, 7 — billing, feature requests, sync issues, and pricing
--      questions are semantically distant from authentication failures.
--      Expected similarity: lower (~0.55-0.70).
--
--   Result set: exactly 5 rows (LIMIT 5 in vector_search call).
--   Columns: ticket_id, subject, status, priority, customer name, similarity score.
--
\echo '=== Q1: Find tickets similar to "SSO login failure" (ticket 1) ==='
SELECT
    t.id AS ticket_id,
    t.subject,
    t.status,
    t.priority,
    c.name AS customer,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.vector_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 5, 'ticket'
) vs
JOIN support.tickets t ON t.id = vs.source_id::int
JOIN support.customers c ON c.id = t.customer_id
ORDER BY vs.similarity DESC;

-- =============================================================================
-- 2. RECOMMEND KB ARTICLES FOR AN OPEN TICKET
-- Use case: Auto-suggest relevant help articles when a ticket comes in
-- =============================================================================
--
-- HOW IT WORKS:
--   Takes ticket 4's base embedding (CloudSync file sync failure) and searches
--   only kb_article entities. The JOIN to support.kb_articles adds the extra
--   filter kb.is_published = TRUE (defense against unpublished drafts).
--
-- EXPECTED RESULTS:
--   Ticket 4 is about CloudSync Pro files not syncing, mentions "paused" icon,
--   Windows 11, and special characters causing issues.
--
--   1. KB Article 2 "Troubleshooting CloudSync Pro sync issues" — near-perfect
--      topical match. The article specifically covers sync failures, special
--      characters in file names, restarting sync, and version issues. This is
--      exactly the article an agent would send to the customer.
--      Expected similarity: highest (~0.85-0.95).
--   2. KB Article 5 "Sharing files and folders in DataVault" — tangentially
--      related (file operations) but different product and different problem.
--      Expected similarity: moderate (~0.60-0.75).
--   3. KB Articles 1, 3, 4 — SSO setup, API rate limits, and password resets
--      are unrelated to file sync issues.
--      Expected similarity: low (~0.50-0.65).
--
--   Result set: up to 5 rows (all 5 KB articles if all are published).
--   Columns: article_id, title, category, comma-separated tags, similarity.
--
\echo '=== Q2: KB articles relevant to sync issue (ticket 4) ==='
SELECT
    kb.id AS article_id,
    kb.title,
    kb.category,
    array_to_string(kb.tags, ', ') AS tags,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.vector_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '4'
       AND emb.embedding_type = 'base'),
    'base', 5, 'kb_article'
) vs
JOIN support.kb_articles kb ON kb.id = vs.source_id::int
WHERE kb.is_published = TRUE
ORDER BY vs.similarity DESC;

-- =============================================================================
-- 3. CONTEXT-ENRICHED SIMILARITY: BASE vs LOCAL_CONTEXT EMBEDDINGS
-- Use case: Compare how context (priority, customer plan, product) shifts results
-- =============================================================================
--
-- HOW IT WORKS:
--   Runs TWO separate vector searches for ticket 5 (API rate limit exceeded):
--   - base_results: searches using ticket 5's base embedding (content only)
--     against all base embeddings. This captures pure semantic text similarity.
--   - context_results: searches using ticket 5's local_context embedding
--     (content + context attributes like "priority: high", "product: API Gateway",
--     "customer_plan: enterprise") against all local_context embeddings.
--   Then LEFT JOINs them and computes a blended score (60% base + 40% context).
--   p_entity_type=NULL means both tickets AND KB articles are returned.
--
-- EXPECTED RESULTS:
--   Ticket 5 context includes: high priority, technical, enterprise plan,
--   API Gateway product, agent Sam Williams, Big Bank Financial.
--
--   BASE similarity (pure content): Ticket 8 should rank high because it's also
--   about API Gateway and technical integration. KB Article 3 (API rate limits)
--   should also be very close. Tickets about other products rank lower.
--
--   CONTEXT similarity: With context enrichment, ticket 8 should get an extra
--   boost because it shares: same product (API Gateway), same agent (Sam Williams),
--   same category (technical), same plan (enterprise). Ticket 1 also shares
--   high priority + technical + enterprise, so it may rise in context ranking
--   compared to its base ranking. Free/pro plan tickets may drop.
--
--   BLENDED SCORE shifts: Look for cases where context_similarity differs from
--   base_similarity — these show the effect of contextual enrichment. Entities
--   that share product/plan/priority will have context_similarity > base_similarity
--   relative to entities that only share text content.
--
--   Result set: up to 10 rows covering both tickets and KB articles.
--   The self-match (ticket 5) will have base_similarity=1.0 and context_similarity=1.0.
--
\echo '=== Q3: Base vs context-enriched search for ticket 5 (API rate limit) ==='
WITH base_results AS (
    SELECT
        vs.source_id,
        vs.base_content->>'subject' AS subject,
        vs.similarity AS base_sim
    FROM contextrag.vector_search(
        (SELECT emb.embedding
         FROM contextrag.entity_embeddings emb
         JOIN contextrag.entities e ON e.id = emb.entity_id
         WHERE e.source_table = 'tickets' AND e.source_id = '5'
           AND emb.embedding_type = 'base'),
        'base', 10, NULL
    ) vs
),
context_results AS (
    SELECT
        vs.source_id,
        vs.similarity AS ctx_sim
    FROM contextrag.vector_search(
        (SELECT emb.embedding
         FROM contextrag.entity_embeddings emb
         JOIN contextrag.entities e ON e.id = emb.entity_id
         WHERE e.source_table = 'tickets' AND e.source_id = '5'
           AND emb.embedding_type = 'local_context'),
        'local_context', 10, NULL
    ) vs
)
SELECT
    br.source_id,
    br.subject,
    ROUND(br.base_sim::numeric, 4) AS base_similarity,
    ROUND(COALESCE(cr.ctx_sim, 0)::numeric, 4) AS context_similarity,
    ROUND(((br.base_sim * 0.6) + (COALESCE(cr.ctx_sim, 0) * 0.4))::numeric, 4) AS blended_score
FROM base_results br
LEFT JOIN context_results cr ON cr.source_id = br.source_id
ORDER BY blended_score DESC;

-- =============================================================================
-- 4. FIND ENTERPRISE CUSTOMER TICKETS SIMILAR TO A BUG REPORT
-- Use case: Prioritize enterprise tickets that match a known bug pattern
-- =============================================================================
--
-- HOW IT WORKS:
--   Uses hybrid_search() which combines vector similarity with a JSONB metadata
--   filter. The metadata filter '{"customer_plan": "enterprise"}' matches against
--   the entities.metadata column, which was populated during register_entity()
--   with {"product": "...", "customer_plan": "..."}.
--
--   The query vector is ticket 4 (CloudSync sync failure, urgent bug).
--   Only entities whose metadata contains customer_plan="enterprise" pass the filter.
--
-- EXPECTED RESULTS:
--   Ticket 4 itself is a PRO plan ticket (Lisa Chen, Innovate Co), so it will
--   NOT appear in results — it fails the enterprise metadata filter.
--
--   Enterprise tickets in the dataset:
--     Ticket 1: SSO login failure      (Acme Corp, enterprise)
--     Ticket 3: Folder sharing request  (Global Retail, enterprise)
--     Ticket 5: API rate limit          (Big Bank, enterprise)
--     Ticket 8: API Gateway integration (Healthcare Plus, enterprise)
--
--   Among these, ticket 1 and ticket 3 might have moderate similarity to a sync
--   bug (both deal with product issues), while tickets 5 and 8 (API Gateway)
--   are semantically more distant from file sync problems.
--
--   This query demonstrates a real-world scenario: "A CloudSync bug is reported.
--   Show me which enterprise customers might also be affected by similar issues."
--
--   Result set: up to 4 rows (only 4 enterprise tickets exist).
--   No minimum similarity threshold is applied (p_min_similarity=0.0).
--
\echo '=== Q4: Enterprise tickets similar to sync bug (ticket 4) ==='
SELECT
    t.id AS ticket_id,
    t.subject,
    t.priority,
    c.name AS customer,
    c.company,
    c.plan_type,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.hybrid_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '4'
       AND emb.embedding_type = 'base'),
    'base', 10, 'ticket',
    '{"customer_plan": "enterprise"}'::jsonb,
    0.0
) vs
JOIN support.tickets t ON t.id = vs.source_id::int
JOIN support.customers c ON c.id = t.customer_id
ORDER BY vs.similarity DESC;

-- =============================================================================
-- 5. CROSS-ENTITY SEARCH: TICKETS + KB ARTICLES RANKED TOGETHER
-- Use case: Unified search across all entity types for an agent's query
-- =============================================================================
--
-- HOW IT WORKS:
--   Uses ticket 6's embedding ("Password reset email not received" on SecureAuth)
--   as the query vector. p_entity_type=NULL means ALL entity types (tickets and
--   KB articles) are searched and ranked together in a single result set.
--   The CASE expression displays the appropriate title field per entity type.
--
-- EXPECTED RESULTS:
--   Ticket 6 is about: SecureAuth password reset, email not received, user locked out.
--
--   Expected ranking (mixed tickets and KB articles):
--   1. Ticket 6 itself — similarity = 1.0000 (self-match).
--   2. KB Article 4 "How to reset your SecureAuth password" — this article directly
--      addresses the exact issue: password reset, email not received troubleshooting,
--      and locked account steps. Extremely high semantic match.
--      Expected similarity: very high (~0.85-0.95).
--   3. KB Article 1 "How to configure SSO with Azure AD" — also about SecureAuth
--      authentication, but focused on SSO setup, not password reset.
--      Expected similarity: moderate-high (~0.70-0.85).
--   4. Ticket 1 "Unable to login with SSO after password change" — same product
--      (SecureAuth), both are login/authentication issues. However, one is SSO-based
--      and the other is direct password reset.
--      Expected similarity: moderate-high (~0.70-0.85).
--   5. Other tickets/articles — less relevant. Billing, sync, API topics are distant.
--
--   KEY INSIGHT: This query shows the power of cross-entity search. A support agent
--   searching for "password reset" gets BOTH the relevant KB article to share with
--   the customer AND similar past tickets to learn from — in one query.
--
--   Result set: up to 10 rows, a mix of 'ticket' and 'kb_article' entity types.
--
\echo '=== Q5: Unified search for "authentication password SSO" across all entities ==='
SELECT
    vs.entity_type,
    vs.source_id,
    CASE
        WHEN vs.entity_type = 'ticket' THEN vs.base_content->>'subject'
        WHEN vs.entity_type = 'kb_article' THEN vs.base_content->>'title'
    END AS title,
    ROUND(vs.similarity::numeric, 4) AS similarity
FROM contextrag.vector_search(
    -- Use ticket 6 (password reset issue) as the query vector
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '6'
       AND emb.embedding_type = 'base'),
    'base', 10, NULL
) vs
ORDER BY vs.similarity DESC;

-- =============================================================================
-- 6. WEIGHTED MULTI-EMBEDDING SEARCH
-- Use case: Balance content relevance (base) with contextual match (plan, product)
-- =============================================================================
--
-- HOW IT WORKS:
--   Uses multi_embedding_search() which searches BOTH the base and local_context
--   embedding spaces simultaneously, then combines them with configurable weights.
--   Here: 60% base (content) + 40% context (attributes like product, plan, priority).
--
--   The query vector is ticket 1's BASE embedding. The function uses this SAME
--   vector against both embedding types — it does NOT use the local_context
--   embedding as query. This means context_similarity measures how close
--   ticket 1's content-only embedding is to each entity's context-enriched embedding.
--
-- EXPECTED RESULTS:
--   Ticket 1 is: SSO login on SecureAuth, high priority, technical, enterprise.
--
--   base_sim column: Pure text similarity. Ticket 6 (password reset on SecureAuth)
--   and KB Article 1/4 (SSO setup / password reset on SecureAuth) should rank high.
--
--   ctx_sim column: Measures how well the query text aligns with each entity's
--   enriched context embedding. Entities that share SecureAuth product context
--   and enterprise/technical context will score higher here than their base_sim
--   alone would suggest.
--
--   combined column: The blended 0.6/0.4 score. This should produce a more
--   nuanced ranking than base-only search. For example:
--   - Ticket 6 has high base_sim (same product, similar issue) but lower ctx_sim
--     (free plan vs enterprise, unassigned vs Tom Anderson). The blend balances this.
--   - Ticket 5 may have lower base_sim (different topic) but higher ctx_sim
--     (both enterprise, both high priority, both technical). The blend lifts it.
--
--   Result set: up to 10 rows, both tickets and KB articles.
--   The self-match (ticket 1) will have base_sim=1.0, ctx_sim close to 1.0,
--   combined close to 1.0.
--
\echo '=== Q6: Multi-embedding search weighted 60% base / 40% context ==='
SELECT
    mes.source_id,
    mes.entity_type,
    CASE
        WHEN mes.entity_type = 'ticket' THEN mes.base_content->>'subject'
        WHEN mes.entity_type = 'kb_article' THEN mes.base_content->>'title'
    END AS title,
    ROUND(mes.base_similarity::numeric, 4) AS base_sim,
    ROUND(mes.context_similarity::numeric, 4) AS ctx_sim,
    ROUND(mes.combined_score::numeric, 4) AS combined
FROM contextrag.multi_embedding_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    0.6, 0.4, 10, NULL
) mes
ORDER BY mes.combined_score DESC;

-- =============================================================================
-- 7. CONTEXT-AWARE SEARCH: URGENT TICKETS ONLY
-- Use case: Find semantically similar tickets filtered to urgent priority
-- =============================================================================
--
-- HOW IT WORKS:
--   Uses context_aware_search() which first filters entities by context attributes
--   (here: context_type='priority', context_key='ticket_priority', context_value='urgent'),
--   then runs vector similarity only on the matching subset.
--   Also filtered to entity_type='ticket'.
--
-- EXPECTED RESULTS:
--   Only ONE ticket in the dataset has priority='urgent':
--     Ticket 4: "Files not syncing - data loss concern" (CloudSync, urgent, bug)
--
--   So this query will return at most 1 row — ticket 4.
--   Its similarity to ticket 1 (SSO login issue) will likely be moderate
--   (~0.55-0.70) since they are about completely different products and issues.
--
--   The context_matches column will show ALL context attributes for ticket 4,
--   not just the one that matched the filter. This includes:
--   - priority: ticket_priority = urgent (weight 1.0)
--   - status: ticket_status = in_progress (weight 0.9)
--   - category: ticket_category = bug (weight 1.0)
--   - product: product_name = CloudSync Pro (weight 0.9)
--   - customer: customer_name = Lisa Chen (weight 0.7)
--   - customer: customer_company = Innovate Co (weight 0.6)
--   - customer: plan_type = pro (weight 0.8)
--   - agent: assigned_agent = Tom Anderson (weight 0.5)
--   - agent: agent_team = technical (weight 0.6)
--
--   KEY INSIGHT: This demonstrates a common support workflow — "Show me all urgent
--   tickets that look similar to this one" — combining semantic search with
--   structured attribute filtering. If no urgent tickets are semantically close,
--   you still see them all (no min_similarity is applied).
--
\echo '=== Q7: Similar to ticket 1 but only urgent priority tickets ==='
SELECT
    cas.source_id,
    cas.base_content->>'subject' AS subject,
    ROUND(cas.similarity::numeric, 4) AS similarity,
    cas.context_matches
FROM contextrag.context_aware_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '1'
       AND emb.embedding_type = 'base'),
    'base', 10, 'ticket',
    'priority', 'ticket_priority', 'urgent'
) cas
ORDER BY cas.similarity DESC;

-- =============================================================================
-- 8. CONTEXT-AWARE SEARCH: ONLY TECHNICAL CATEGORY
-- Use case: Find similar technical issues, excluding billing/feature requests
-- =============================================================================
--
-- HOW IT WORKS:
--   Same as Q7 but filters on context_type='category', context_key='ticket_category',
--   context_value='technical'. Uses ticket 5 (API rate limit) as the query vector.
--
-- EXPECTED RESULTS:
--   Tickets with category='technical':
--     Ticket 1: "Unable to login with SSO after password change" (SecureAuth, high)
--     Ticket 5: "API rate limit exceeded unexpectedly"           (API Gateway, high) — self-match
--     Ticket 6: "Password reset email not received"              (SecureAuth, medium)
--     Ticket 8: "How to integrate API Gateway with our legacy"   (API Gateway, medium)
--
--   Excluded by the filter (not technical):
--     Ticket 2: billing
--     Ticket 3: feature_request
--     Ticket 4: bug
--     Ticket 7: billing
--
--   Expected ranking against ticket 5 (API rate limit):
--   1. Ticket 5 itself — similarity = 1.0000.
--   2. Ticket 8 — also about API Gateway, also technical. Both discuss API management
--      and integration challenges. Expected similarity: high (~0.75-0.90).
--   3. Ticket 1 — technical but about authentication (different domain).
--      Expected similarity: moderate (~0.60-0.75).
--   4. Ticket 6 — technical but about password resets (different domain).
--      Expected similarity: moderate (~0.55-0.70).
--
--   Result set: exactly 4 rows (4 technical tickets).
--
\echo '=== Q8: Technical tickets similar to API rate limit issue (ticket 5) ==='
SELECT
    cas.source_id,
    cas.base_content->>'subject' AS subject,
    ROUND(cas.similarity::numeric, 4) AS similarity
FROM contextrag.context_aware_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '5'
       AND emb.embedding_type = 'base'),
    'base', 10, 'ticket',
    'category', 'ticket_category', 'technical'
) cas
ORDER BY cas.similarity DESC;

-- =============================================================================
-- 9. FIND KB ARTICLES RELEVANT TO ALL OPEN TICKETS (Batch Recommendation)
-- Use case: Dashboard showing top KB article suggestion per open ticket
-- =============================================================================
--
-- HOW IT WORKS:
--   For EACH open/in_progress/waiting ticket, uses CROSS JOIN LATERAL to call
--   vector_search() with that ticket's embedding and find the top 3 KB articles.
--   DISTINCT ON (t.id) with ORDER BY t.id, vs.similarity DESC picks only the
--   single best-matching KB article per ticket.
--
--   This is a powerful pattern: it turns a per-entity search function into a
--   batch operation across all qualifying entities.
--
-- EXPECTED RESULTS:
--   Open/in_progress/waiting tickets (7 of 8 — only ticket 7 is 'resolved'):
--
--   Ticket 1 (SSO login, in_progress) →
--     Best match: KB Article 1 "How to configure SSO with Azure AD"
--     Reason: Both about SecureAuth SSO. The article's troubleshooting section
--     directly addresses "Authentication failed" errors.
--
--   Ticket 2 (Upgrade question, open) →
--     Best match: Likely KB Article 2 "Troubleshooting CloudSync Pro sync issues"
--     or Article 5 (DataVault sharing). Neither is about billing/upgrades, so
--     all matches will have relatively low similarity. This exposes a gap in the
--     knowledge base — there's no article about plan upgrades.
--
--   Ticket 3 (Folder sharing, open) →
--     Best match: KB Article 5 "Sharing files and folders in DataVault"
--     Reason: Exact product match (DataVault) and topic match (sharing/permissions).
--     The article even mentions folder-level sharing for Enterprise.
--
--   Ticket 4 (Sync failure, in_progress) →
--     Best match: KB Article 2 "Troubleshooting CloudSync Pro sync issues"
--     Reason: Same product (CloudSync Pro), exact issue match (sync not working,
--     special characters, version-specific bugs).
--
--   Ticket 5 (API rate limit, waiting) →
--     Best match: KB Article 3 "Understanding API Gateway rate limits"
--     Reason: Same product (API Gateway), exact topic (rate limiting, 429 errors,
--     enterprise limits of 10k req/min).
--
--   Ticket 6 (Password reset, open) →
--     Best match: KB Article 4 "How to reset your SecureAuth password"
--     Reason: Same product (SecureAuth), exact issue (password reset, email not
--     received, account locked out).
--
--   Ticket 8 (API Gateway integration, in_progress) →
--     Best match: KB Article 3 "Understanding API Gateway rate limits"
--     Reason: Same product (API Gateway). Though the article is about rate limits
--     not SOAP-to-REST integration, it's the closest KB content available.
--
--   Result set: 7 rows (one per open/in_progress/waiting ticket).
--   This query effectively builds an auto-suggestion dashboard.
--
\echo '=== Q9: Best KB article recommendation per open ticket ==='
SELECT DISTINCT ON (t.id)
    t.id AS ticket_id,
    t.subject AS ticket_subject,
    t.priority,
    kb.title AS recommended_article,
    ROUND(vs.similarity::numeric, 4) AS relevance
FROM support.tickets t
JOIN contextrag.entities e ON e.source_table = 'tickets' AND e.source_id = t.id::text
JOIN contextrag.entity_embeddings emb ON emb.entity_id = e.id AND emb.embedding_type = 'base'
CROSS JOIN LATERAL (
    SELECT vs2.*
    FROM contextrag.vector_search(emb.embedding, 'base', 3, 'kb_article') vs2
) vs
JOIN support.kb_articles kb ON kb.id = vs.source_id::int AND kb.is_published = TRUE
WHERE t.status IN ('open', 'in_progress', 'waiting')
ORDER BY t.id, vs.similarity DESC;

-- =============================================================================
-- 10. EMBEDDING COVERAGE & QUALITY REPORT
-- Use case: Monitor which entities have embeddings and detect stale ones
-- =============================================================================
--
-- HOW IT WORKS:
--   For each active entity, checks the entity_embeddings table to determine:
--   - Which embedding types exist (base, local_context, or both)
--   - When the most recent embedding was generated
--   - Whether the entity has been updated AFTER its embedding was created (STALE)
--   Uses correlated subqueries against entity_embeddings for each entity.
--
-- EXPECTED RESULTS:
--   After running both batch_embed.py commands (base + local_context), every
--   entity should have status = 'CURRENT' with embedding_types = {base, local_context}.
--
--   13 total rows (8 tickets + 5 KB articles):
--     All should show:
--       embedding_types: {base, local_context}
--       embedding_status: CURRENT
--
--   If you run this BEFORE batch_embed.py:
--     All will show: embedding_types = {}, embedding_status = MISSING
--
--   If you run this AFTER updating a ticket (e.g., changing its subject) but
--   BEFORE re-running batch_embed.py:
--     That ticket will show: embedding_status = STALE (entity_updated_at > latest_embedding_at)
--     All others remain CURRENT.
--
--   Ordering: STALE/MISSING sort first (DESC on embedding_status string), so
--   entities needing attention appear at the top of the report.
--
--   This query is essential for monitoring embedding freshness in production.
--
\echo '=== Q10: Embedding coverage report ==='
SELECT
    e.entity_type,
    e.source_id,
    CASE
        WHEN e.entity_type = 'ticket' THEN e.base_content->>'subject'
        WHEN e.entity_type = 'kb_article' THEN e.base_content->>'title'
    END AS title,
    COALESCE(
        (SELECT array_agg(emb.embedding_type ORDER BY emb.embedding_type)
         FROM contextrag.entity_embeddings emb WHERE emb.entity_id = e.id),
        ARRAY[]::TEXT[]
    ) AS embedding_types,
    COALESCE(
        (SELECT MAX(emb.created_at)
         FROM contextrag.entity_embeddings emb WHERE emb.entity_id = e.id),
        NULL
    ) AS latest_embedding_at,
    e.updated_at AS entity_updated_at,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM contextrag.entity_embeddings emb WHERE emb.entity_id = e.id)
            THEN 'MISSING'
        WHEN e.updated_at > (SELECT MAX(emb.created_at) FROM contextrag.entity_embeddings emb WHERE emb.entity_id = e.id)
            THEN 'STALE'
        ELSE 'CURRENT'
    END AS embedding_status
FROM contextrag.entities e
WHERE e.is_active = TRUE
ORDER BY embedding_status DESC, e.entity_type, e.source_id::int;

-- =============================================================================
-- 11. NEAREST NEIGHBOR CLUSTER ANALYSIS
-- Use case: Discover which tickets naturally cluster together by embedding similarity
-- =============================================================================
--
-- HOW IT WORKS:
--   Computes pairwise cosine similarity between every pair of ticket base embeddings.
--   Uses a self-join with the condition e1.source_id < e2.source_id to avoid
--   duplicate pairs (A,B and B,A) and self-comparisons (A,A).
--   Does NOT use the vector_search() function — instead computes raw <=> distance
--   directly. This means HNSW index is NOT used; it's a brute-force all-pairs scan.
--
-- EXPECTED RESULTS:
--   With 8 tickets, there are C(8,2) = 28 unique pairs.
--   All 28 rows will be returned, sorted by similarity descending.
--
--   Expected high-similarity clusters:
--
--   CLUSTER 1 — Authentication/SecureAuth:
--     (1, 6): "SSO login failure" ↔ "Password reset not received"
--     Both are SecureAuth authentication issues. Expected: ~0.80-0.90.
--
--   CLUSTER 2 — API Gateway:
--     (5, 8): "API rate limit exceeded" ↔ "API Gateway legacy integration"
--     Both are API Gateway technical issues. Expected: ~0.75-0.88.
--
--   CLUSTER 3 — CloudSync/Billing:
--     (2, 7): "Upgrade question" ↔ "Double charged"
--     Both are CloudSync Pro billing-related tickets. Expected: ~0.70-0.82.
--     (2, 4) or (4, 7): Ticket 4 (sync bug) shares CloudSync product with 2 and 7.
--
--   LOW SIMILARITY pairs (cross-domain):
--     (3, 5): "DataVault folder sharing" ↔ "API rate limits" — very different.
--     (4, 6): "File sync bug" ↔ "Password reset" — different products/issues.
--     Expected: ~0.50-0.65.
--
--   This analysis reveals natural topic clusters in your support data without
--   any manual tagging — purely from embedding geometry.
--
\echo '=== Q11: Pairwise similarity between all tickets ==='
SELECT
    e1.source_id AS ticket_a,
    t1.subject AS subject_a,
    e2.source_id AS ticket_b,
    t2.subject AS subject_b,
    ROUND((1 - (emb1.embedding <=> emb2.embedding))::numeric, 4) AS similarity
FROM contextrag.entity_embeddings emb1
JOIN contextrag.entities e1 ON e1.id = emb1.entity_id
JOIN support.tickets t1 ON t1.id = e1.source_id::int
CROSS JOIN contextrag.entity_embeddings emb2
JOIN contextrag.entities e2 ON e2.id = emb2.entity_id
JOIN support.tickets t2 ON t2.id = e2.source_id::int
WHERE emb1.embedding_type = 'base'
  AND emb2.embedding_type = 'base'
  AND e1.entity_type = 'ticket'
  AND e2.entity_type = 'ticket'
  AND e1.source_id < e2.source_id  -- avoid duplicates and self-matches
ORDER BY similarity DESC;

-- =============================================================================
-- 12. TICKET-TO-KB RELEVANCE MATRIX
-- Use case: Show which KB articles are most relevant to each ticket category
-- =============================================================================
--
-- HOW IT WORKS:
--   Groups tickets by their category context attribute (technical, billing,
--   feature_request, bug), then for each category computes the average cosine
--   similarity between all tickets in that category and each KB article.
--   Uses raw <=> distance (brute-force, no HNSW).
--
--   NOTE: The CROSS JOIN creates a Cartesian product of ticket embeddings × KB
--   article embeddings, then GROUP BY aggregates into category × article averages.
--
-- EXPECTED RESULTS:
--   4 categories × 5 KB articles = 20 rows.
--
--   "technical" (tickets 1, 5, 6, 8):
--     KB Article 1 "SSO with Azure AD"       → high avg (tickets 1 & 6 are SecureAuth)
--     KB Article 4 "Password reset"           → high avg (ticket 6 is password reset)
--     KB Article 3 "API Gateway rate limits"  → high avg (tickets 5 & 8 are API Gateway)
--     KB Article 2 "CloudSync sync issues"    → lower avg (no technical tickets are CloudSync)
--     KB Article 5 "DataVault sharing"        → lowest avg
--     ticket_count: 4 for each article row
--
--   "billing" (tickets 2, 7):
--     KB Article 2 "CloudSync sync issues"    → moderate (both are CloudSync Pro product)
--     All others                              → low (billing topics have no KB coverage)
--     ticket_count: 2 for each article row
--
--   "bug" (ticket 4 only):
--     KB Article 2 "CloudSync sync issues"    → highest (same product, sync-related)
--     ticket_count: 1 for each article row
--
--   "feature_request" (ticket 3 only):
--     KB Article 5 "DataVault sharing"        → highest (same product, sharing topic)
--     ticket_count: 1 for each article row
--
--   This matrix reveals KB coverage gaps: if a category's best article similarity
--   is below ~0.70, you probably need to write more articles for that topic.
--
\echo '=== Q12: Average similarity between ticket categories and KB articles ==='
SELECT
    ec.context_value AS ticket_category,
    kb.title AS article_title,
    ROUND(AVG(1 - (t_emb.embedding <=> kb_emb.embedding))::numeric, 4) AS avg_similarity,
    COUNT(*) AS ticket_count
FROM contextrag.entity_context ec
JOIN contextrag.entities e ON e.id = ec.entity_id AND e.entity_type = 'ticket'
JOIN contextrag.entity_embeddings t_emb ON t_emb.entity_id = e.id AND t_emb.embedding_type = 'base'
CROSS JOIN (
    SELECT kb_e.id AS entity_id, kb_a.title, kb_emb2.embedding
    FROM contextrag.entities kb_e
    JOIN support.kb_articles kb_a ON kb_a.id = kb_e.source_id::int
    JOIN contextrag.entity_embeddings kb_emb2 ON kb_emb2.entity_id = kb_e.id AND kb_emb2.embedding_type = 'base'
    WHERE kb_e.entity_type = 'kb_article'
) kb
JOIN contextrag.entity_embeddings kb_emb ON kb_emb.entity_id = kb.entity_id AND kb_emb.embedding_type = 'base'
WHERE ec.context_key = 'ticket_category'
GROUP BY ec.context_value, kb.title
ORDER BY ec.context_value, avg_similarity DESC;

-- =============================================================================
-- 13. FIND DUPLICATE/NEAR-DUPLICATE TICKETS
-- Use case: Detect tickets that may be duplicates based on embedding proximity
-- =============================================================================
--
-- HOW IT WORKS:
--   Same pairwise comparison as Q11, but adds a hard filter:
--   (1 - cosine_distance) > 0.90 — only returns pairs with >90% similarity.
--   Also shows customer_id for each ticket so you can see if duplicates are
--   from the same or different customers.
--
-- EXPECTED RESULTS:
--   With the current seed data, NO ticket pairs are likely to exceed 0.90 similarity.
--   Each ticket describes a genuinely different issue:
--   - Tickets 1 & 6 are the most similar (both SecureAuth auth issues) but one is
--     about SSO token refresh and the other about password reset email delivery.
--     Expected similarity: ~0.80-0.88, likely below 0.90 threshold.
--   - Tickets 5 & 8 are both API Gateway but one is rate limiting and the other
--     is SOAP-to-REST integration. Expected: ~0.75-0.85.
--
--   RESULT SET: Most likely 0 rows (empty) with this seed data.
--
--   In a production system with thousands of tickets, this query catches:
--   - Customers submitting the same issue twice
--   - Multiple customers reporting the same outage
--   - Tickets that should be merged
--
--   If you lower the threshold to 0.80, you would likely see the (1,6) and (5,8)
--   pairs appear. Tuning this threshold is important: too low = false positives,
--   too high = missed duplicates.
--
\echo '=== Q13: Potential duplicate tickets (similarity > 0.90) ==='
SELECT
    e1.source_id AS ticket_a,
    t1.subject AS subject_a,
    t1.customer_id AS customer_a,
    e2.source_id AS ticket_b,
    t2.subject AS subject_b,
    t2.customer_id AS customer_b,
    ROUND((1 - (emb1.embedding <=> emb2.embedding))::numeric, 4) AS similarity
FROM contextrag.entity_embeddings emb1
JOIN contextrag.entities e1 ON e1.id = emb1.entity_id AND e1.entity_type = 'ticket'
JOIN support.tickets t1 ON t1.id = e1.source_id::int
CROSS JOIN contextrag.entity_embeddings emb2
JOIN contextrag.entities e2 ON e2.id = emb2.entity_id AND e2.entity_type = 'ticket'
JOIN support.tickets t2 ON t2.id = e2.source_id::int
WHERE emb1.embedding_type = 'base'
  AND emb2.embedding_type = 'base'
  AND e1.source_id < e2.source_id
  AND (1 - (emb1.embedding <=> emb2.embedding)) > 0.90
ORDER BY similarity DESC;

-- =============================================================================
-- 14. AGENT EXPERTISE MATCHING
-- Use case: Find which agent has resolved the most tickets similar to a new one
-- =============================================================================
--
-- HOW IT WORKS:
--   Takes ticket 6's embedding (password reset, SecureAuth, unassigned) and finds
--   all similar tickets via vector_search. Then JOINs to support.tickets and
--   support.agents to see which agents handled those similar tickets. Groups by
--   agent and computes: count of similar tickets handled, average similarity,
--   and max similarity.
--
--   Excludes ticket 6 itself (vs.source_id != '6') since it's unassigned.
--   The WHERE t.agent_id IS NOT NULL filters out other unassigned tickets (3 and 6).
--
-- EXPECTED RESULTS:
--   Ticket 6 is about SecureAuth password reset. The most similar assigned tickets:
--
--   Tom Anderson (technical team):
--     Handles ticket 1 (SSO login on SecureAuth) — high similarity to ticket 6
--     Handles ticket 4 (CloudSync sync) — low similarity to ticket 6
--     similar_tickets_handled: 2
--     avg_similarity: moderate (dragged down by ticket 4)
--     max_similarity: high (from ticket 1)
--
--   Jane Martinez (billing team):
--     Handles ticket 2 (upgrade question) — low similarity
--     Handles ticket 7 (double charge) — low similarity
--     similar_tickets_handled: 2
--     avg_similarity: low
--     max_similarity: low
--
--   Sam Williams (technical team):
--     Handles ticket 5 (API rate limit) — moderate similarity
--     Handles ticket 8 (API integration) — moderate similarity
--     similar_tickets_handled: 2
--     avg_similarity: moderate
--     max_similarity: moderate
--
--   EXPECTED WINNER: Tom Anderson — because he handled ticket 1 (SSO/SecureAuth),
--   which is the most semantically similar assigned ticket to the password reset
--   issue. His max_similarity should be the highest.
--
--   This enables intelligent ticket routing: assign new tickets to agents who
--   have the most experience with similar issues, not just by category tag.
--
\echo '=== Q14: Best agent match for new password reset ticket (ticket 6) ==='
SELECT
    a.name AS agent_name,
    a.team,
    COUNT(*) AS similar_tickets_handled,
    ROUND(AVG(vs.similarity)::numeric, 4) AS avg_similarity,
    ROUND(MAX(vs.similarity)::numeric, 4) AS max_similarity
FROM contextrag.vector_search(
    (SELECT emb.embedding
     FROM contextrag.entity_embeddings emb
     JOIN contextrag.entities e ON e.id = emb.entity_id
     WHERE e.source_table = 'tickets' AND e.source_id = '6'
       AND emb.embedding_type = 'base'),
    'base', 20, 'ticket'
) vs
JOIN support.tickets t ON t.id = vs.source_id::int
JOIN support.agents a ON a.id = t.agent_id
WHERE t.agent_id IS NOT NULL
  AND vs.source_id != '6'
GROUP BY a.id, a.name, a.team
ORDER BY avg_similarity DESC;

-- =============================================================================
-- 15. CONTEXT EMBEDDING DRIFT ANALYSIS
-- Use case: See how much the context embedding differs from the base embedding
-- =============================================================================
--
-- HOW IT WORKS:
--   For each entity, compares its base embedding (content only) against its
--   local_context embedding (content + context attributes) using cosine similarity.
--   - base_ctx_similarity: How similar the two embeddings are (1.0 = identical).
--   - drift: How much they differ (= cosine distance = 1 - similarity).
--     Drift of 0 means context added no signal; drift > 0 means context shifted
--     the entity's position in embedding space.
--   - context_count: Number of context attributes attached to the entity.
--
-- EXPECTED RESULTS:
--   All 13 entities (8 tickets + 5 KB articles) will appear.
--
--   Entities with MORE context attributes should generally show HIGHER drift,
--   because more context text is appended to the base content before embedding.
--
--   Tickets have 7-9 context attributes each:
--     status, priority, category, customer_name, customer_company, plan_type,
--     product_name, assigned_agent, agent_team
--     Expected drift: moderate (~0.05-0.20)
--
--   KB Articles have 4-7 context attributes each:
--     article_category, product_name, and 2-4 tags
--     Expected drift: moderate (~0.05-0.15)
--
--   Entities with SHORT base content relative to their context will show MORE
--   drift (context dominates the embedding). Entities with LONG base content
--   will show LESS drift (context is diluted).
--
--   For example:
--   - Ticket 3 "Request: Add folder-level sharing permissions" has a moderate
--     description but also has context about DataVault, enterprise, Global Retail.
--   - KB Article 3 "Understanding API Gateway rate limits" has very long content
--     (rate limit tiers, headers, best practices) so context is relatively smaller.
--
--   Sorted by drift DESC — entities most affected by context enrichment appear first.
--   High drift entities are where context_aware_search() and multi_embedding_search()
--   will produce the most different results compared to plain vector_search().
--
\echo '=== Q15: Base vs context embedding drift per entity ==='
SELECT
    e.entity_type,
    e.source_id,
    CASE
        WHEN e.entity_type = 'ticket' THEN e.base_content->>'subject'
        WHEN e.entity_type = 'kb_article' THEN e.base_content->>'title'
    END AS title,
    ROUND((1 - (base_emb.embedding <=> ctx_emb.embedding))::numeric, 4) AS base_ctx_similarity,
    ROUND((1 - (1 - (base_emb.embedding <=> ctx_emb.embedding)))::numeric, 4) AS drift,
    (SELECT COUNT(*) FROM contextrag.entity_context ec WHERE ec.entity_id = e.id) AS context_count
FROM contextrag.entities e
JOIN contextrag.entity_embeddings base_emb
    ON base_emb.entity_id = e.id AND base_emb.embedding_type = 'base'
JOIN contextrag.entity_embeddings ctx_emb
    ON ctx_emb.entity_id = e.id AND ctx_emb.embedding_type = 'local_context'
WHERE e.is_active = TRUE
ORDER BY drift DESC;
