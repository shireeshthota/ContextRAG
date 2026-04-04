-- =============================================================================
-- GraphRAG: Graph-Enhanced Search Examples
-- =============================================================================
-- This file demonstrates the GraphRAG search functions that combine
-- vector similarity with graph structure.
-- Run after:
-- 1. Graph is populated (create_graph.sql)
-- 2. Embeddings are generated (python graph_embed.py)
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, support, "$user", public;

-- =============================================================================
-- SECTION 1: Basic Vector Search
-- =============================================================================

-- Note: These queries require embeddings to be generated first.
-- Use a sample embedding for demonstration (replace with real embedding)

\echo '=== Basic Vector Search (requires embeddings) ==='
\echo 'To run these queries, first generate embeddings using:'
\echo '  python graph_embed.py --embedding-type base'
\echo ''

-- Example: Find tickets similar to a query about "sync not working"
-- In practice, you would first embed the query text and then search
/*
-- Generate query embedding (pseudo-code):
-- query_embedding = embed_text("files not syncing, data loss")

-- Then search:
SELECT * FROM graphrag.vector_search(
    query_embedding,      -- The query embedding vector
    'Ticket',            -- Node type to search
    'base',              -- Embedding type
    5,                   -- Limit
    0.5                  -- Minimum similarity threshold
);
*/

-- =============================================================================
-- SECTION 2: Using GraphRAG Functions
-- =============================================================================

-- Get neighborhood of a specific ticket
\echo '=== Neighborhood of Ticket 1 ==='
SELECT * FROM graphrag.get_node_neighborhood('Ticket', '1');

-- Get extended context (multi-hop)
\echo '=== Extended context for Ticket 1 (2 hops) ==='
SELECT * FROM graphrag.get_extended_context('Ticket', '1', 2, 20);

-- Build graph context as text (for embedding or LLM)
\echo '=== Graph context text for Ticket 1 ==='
SELECT graphrag.build_graph_context_text('Ticket', '1', 1);

-- Find structurally similar tickets (share same neighbors)
\echo '=== Tickets structurally similar to Ticket 1 ==='
SELECT * FROM graphrag.find_structurally_similar('Ticket', '1', 'Ticket', 1, 5);

-- =============================================================================
-- SECTION 3: Subgraph Extraction for LLM
-- =============================================================================

-- Extract a subgraph for LLM context
\echo '=== Subgraph extraction for Ticket 1 (for LLM context) ==='
SELECT graphrag.extract_subgraph_for_llm('Ticket', '1', 2, 15, FALSE);

-- Extract subgraph for a customer
\echo '=== Subgraph extraction for Customer 1 ==='
SELECT graphrag.extract_subgraph_for_llm('Customer', '1', 2, 15, FALSE);

-- =============================================================================
-- SECTION 4: Graph Statistics
-- =============================================================================

\echo '=== Graph Statistics ==='
SELECT * FROM graphrag.get_graph_stats();

-- =============================================================================
-- SECTION 5: Hybrid Search Examples (Vector + Graph Filters)
-- =============================================================================

/*
-- Example: Search for tickets with specific properties
-- First generate query embedding, then:

SELECT * FROM graphrag.hybrid_search(
    query_embedding,
    'Ticket',
    'base',
    5,
    '{"status": "open", "priority": "high"}'::jsonb,  -- Property filter
    0.3                                                -- Min similarity
);
*/

-- =============================================================================
-- SECTION 6: Path-Based Search Examples
-- =============================================================================

/*
-- Find KB articles relevant to a ticket context
-- Uses both semantic similarity and graph paths

SELECT * FROM graphrag.path_similarity_search(
    query_embedding,
    'KBArticle',           -- Target: what we're searching for
    'Ticket',              -- Context: starting point
    '1',                   -- Context source_id
    5,                     -- Limit
    'base'                 -- Embedding type
);

-- This will return KB articles that are:
-- 1. Semantically similar to the query
-- 2. Connected to the ticket via graph paths (same product, etc.)
-- 3. With explanations of WHY they're relevant
*/

-- =============================================================================
-- SECTION 7: Manual Graph-Enhanced Search Pattern
-- =============================================================================

-- This demonstrates the pattern for combining vector search with graph expansion
-- without requiring pre-generated embeddings

\echo '=== Manual graph-enhanced search pattern ==='

-- Step 1: Start with a seed ticket
\echo 'Step 1: Seed ticket (Ticket 1)'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})
    RETURN t.subject as subject, t.status as status, t.priority as priority
$$) AS (subject agtype, status agtype, priority agtype);

-- Step 2: Find related entities via graph
\echo 'Step 2: Related entities via graph'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[r]-(related)
    RETURN type(r) as relationship,
           labels(related)[0] as entity_type,
           CASE
               WHEN labels(related)[0] = 'Customer' THEN related.name
               WHEN labels(related)[0] = 'Product' THEN related.name
               WHEN labels(related)[0] = 'Agent' THEN related.name
               WHEN labels(related)[0] = 'KBArticle' THEN related.title
               ELSE related.source_id
           END as entity_info
$$) AS (relationship agtype, entity_type agtype, entity_info agtype);

-- Step 3: Find other tickets with same product (structural similarity)
\echo 'Step 3: Other tickets about the same product'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t1:Ticket {source_id: '1'})-[:ABOUT_PRODUCT]->(p:Product)<-[:ABOUT_PRODUCT]-(t2:Ticket)
    WHERE t1 <> t2
    RETURN t2.source_id as ticket_id, t2.subject as subject, t2.status as status, p.name as product
$$) AS (ticket_id agtype, subject agtype, status agtype, product agtype);

-- Step 4: Find KB articles for the same product
\echo 'Step 4: KB articles for the same product'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[:ABOUT_PRODUCT]->(p:Product)<-[:DOCUMENTS]-(kb:KBArticle)
    RETURN kb.title as article, kb.category as category, p.name as product
$$) AS (article agtype, category agtype, product agtype);

-- Step 5: Find other tickets from the same customer
\echo 'Step 5: Other tickets from the same customer'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t1:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)
    WHERE t1 <> t2
    RETURN t2.source_id as ticket_id, t2.subject as subject, t2.status as status, c.name as customer
$$) AS (ticket_id agtype, subject agtype, status agtype, customer agtype);

-- =============================================================================
-- SECTION 8: Agent Expertise Discovery
-- =============================================================================

\echo '=== Agent expertise based on resolved tickets ==='

-- Find what products each agent has handled
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ASSIGNED_TO]->(a:Agent),
          (t)-[:ABOUT_PRODUCT]->(p:Product)
    WHERE t.status IN ['resolved', 'closed']
    RETURN a.name as agent, p.name as product, COUNT(t) as resolved_count
    ORDER BY a.name, resolved_count DESC
$$) AS (agent agtype, product agtype, resolved_count agtype);

-- Find the best agent for a given product
\echo '=== Best agent for SecureAuth issues ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ASSIGNED_TO]->(a:Agent),
          (t)-[:ABOUT_PRODUCT]->(p:Product {name: 'SecureAuth'})
    WHERE t.status IN ['resolved', 'closed', 'in_progress']
    RETURN a.name as agent, a.team as team, COUNT(t) as experience_count
    ORDER BY experience_count DESC
    LIMIT 1
$$) AS (agent agtype, team agtype, experience_count agtype);

-- =============================================================================
-- SECTION 9: Customer Journey Analysis
-- =============================================================================

\echo '=== Customer journey for John Smith ==='

-- All interactions for a customer
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (c:Customer {name: 'John Smith'})<-[:CREATED_BY]-(t:Ticket)
    OPTIONAL MATCH (t)-[:ABOUT_PRODUCT]->(p:Product)
    OPTIONAL MATCH (t)-[:ASSIGNED_TO]->(a:Agent)
    OPTIONAL MATCH (t)-[:REFERENCES]->(kb:KBArticle)
    RETURN t.source_id as ticket_id,
           t.subject as subject,
           t.status as status,
           p.name as product,
           a.name as agent,
           kb.title as referenced_article
    ORDER BY t.source_id
$$) AS (ticket_id agtype, subject agtype, status agtype, product agtype, agent agtype, referenced_article agtype);
