-- =============================================================================
-- GraphRAG vs ContextRAG: Comparison Test Cases
-- =============================================================================
-- This file contains test cases that demonstrate when each approach excels.
-- Run after both systems are set up with embeddings.
--
-- Key differences:
-- - ContextRAG: Flat context attributes, no relationships
-- - GraphRAG: Explicit graph relationships, multi-hop traversal
-- =============================================================================

-- Ensure AGE is loaded for GraphRAG
LOAD 'age';
SET search_path = ag_catalog, graphrag, support, "$user", public;

-- =============================================================================
-- TEST 1: Simple Semantic Search
-- =============================================================================
-- Both systems perform equally well on basic semantic similarity.
-- Winner: TIE (both use vector search)

\echo '============================================================'
\echo 'TEST 1: Simple Semantic Search'
\echo '============================================================'
\echo 'Query: "SSO authentication not working"'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  SELECT * FROM contextrag.vector_search(query_embedding, ''base'', 5, ''ticket'');'
\echo ''
\echo 'GraphRAG Approach:'
\echo '  SELECT * FROM graphrag.vector_search(query_embedding, ''Ticket'', ''base'', 5);'
\echo ''
\echo 'Winner: TIE - Both use cosine similarity on embeddings'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 2: Attribute-Filtered Search
-- =============================================================================
-- ContextRAG has simpler syntax; GraphRAG uses Cypher
-- Winner: ContextRAG (simpler)

\echo '============================================================'
\echo 'TEST 2: Attribute-Filtered Search'
\echo '============================================================'
\echo 'Query: Find high priority open tickets about SecureAuth'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  SELECT * FROM contextrag.hybrid_search('
\echo '    query_embedding, ''base'', 5, ''ticket'','
\echo '    ''{"product": "SecureAuth"}''::jsonb'  -- metadata filter
\echo '  ) WHERE priority = ''high'' AND status = ''open'';'
\echo ''
\echo 'GraphRAG Approach:'
\echo '  SELECT * FROM graphrag.hybrid_search('
\echo '    query_embedding, ''Ticket'', ''base'', 5,'
\echo '    ''{"priority": "high", "status": "open"}''::jsonb'
\echo '  );'
\echo ''
\echo 'Winner: ContextRAG - Simpler metadata filtering syntax'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 3: Find Similar Tickets (Same Customer)
-- =============================================================================
-- GraphRAG can traverse relationships; ContextRAG cannot
-- Winner: GraphRAG

\echo '============================================================'
\echo 'TEST 3: Find Similar Tickets (Same Customer)'
\echo '============================================================'
\echo 'Query: Find other tickets from the same customer as Ticket 1'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  -- Must manually query: get customer_id, then filter'
\echo '  -- SELECT * FROM contextrag.context_aware_search(...)'
\echo '  -- WHERE context_value = ''John Smith'';'
\echo '  -- Requires knowing the customer name, can miss connections'
\echo ''
\echo 'GraphRAG Approach:'

SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t1:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)
    WHERE t1 <> t2
    RETURN t2.source_id as ticket_id, t2.subject as subject, c.name as customer
$$) AS (ticket_id agtype, subject agtype, customer agtype);

\echo ''
\echo 'Winner: GraphRAG - Direct relationship traversal'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 4: Multi-hop Discovery
-- =============================================================================
-- GraphRAG can traverse multiple hops; ContextRAG cannot
-- Winner: GraphRAG (significantly)

\echo '============================================================'
\echo 'TEST 4: Multi-hop Discovery'
\echo '============================================================'
\echo 'Query: Find KB articles that helped resolve similar tickets'
\echo '       from the same customer'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  -- Cannot do this in a single query'
\echo '  -- Requires multiple queries and application-level joins'
\echo ''
\echo 'GraphRAG Approach:'

SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t1:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)
    WHERE t1 <> t2 AND t2.status = 'resolved'
    MATCH (t2)-[:REFERENCES]->(kb:KBArticle)
    RETURN DISTINCT kb.title as article, t2.subject as resolved_ticket, c.name as customer
$$) AS (article agtype, resolved_ticket agtype, customer agtype);

\echo ''
\echo 'Winner: GraphRAG - Multi-hop traversal capability'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 5: Agent Expertise Routing
-- =============================================================================
-- GraphRAG can analyze agent history across products
-- Winner: GraphRAG

\echo '============================================================'
\echo 'TEST 5: Agent Expertise Routing'
\echo '============================================================'
\echo 'Query: Which agent has the most experience with CloudSync Pro issues?'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  -- Must manually query tickets, group by agent, count'
\echo '  -- No direct path from agent -> resolved tickets -> products'
\echo ''
\echo 'GraphRAG Approach:'

SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ASSIGNED_TO]->(a:Agent),
          (t)-[:ABOUT_PRODUCT]->(p:Product {name: 'CloudSync Pro'})
    RETURN a.name as agent, a.team as team, COUNT(t) as ticket_count
    ORDER BY ticket_count DESC
    LIMIT 3
$$) AS (agent agtype, team agtype, ticket_count agtype);

\echo ''
\echo 'Winner: GraphRAG - Direct agent-product relationship traversal'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 6: Path-Based Recommendations with Explanations
-- =============================================================================
-- GraphRAG can explain WHY an article is relevant
-- Winner: GraphRAG

\echo '============================================================'
\echo 'TEST 6: Path-Based Recommendations with Explanations'
\echo '============================================================'
\echo 'Query: Why is this KB article relevant to this ticket?'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  -- Returns similarity score only'
\echo '  -- No path-based explanation'
\echo ''
\echo 'GraphRAG Approach:'

SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH path = (t:Ticket {source_id: '1'})-[*1..2]-(kb:KBArticle)
    RETURN kb.title as article,
           [r IN relationships(path) | type(r)] as path_types,
           length(path) as hops,
           CASE length(path)
               WHEN 1 THEN 'Directly referenced by ticket'
               WHEN 2 THEN 'Connected via shared entity'
               ELSE 'Indirectly related'
           END as explanation
$$) AS (article agtype, path_types agtype, hops agtype, explanation agtype);

\echo ''
\echo 'Winner: GraphRAG - Path-based explainability'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 7: Structural Similarity (Non-semantic)
-- =============================================================================
-- GraphRAG can find tickets that share graph neighbors
-- Winner: GraphRAG

\echo '============================================================'
\echo 'TEST 7: Structural Similarity (Non-semantic)'
\echo '============================================================'
\echo 'Query: Find tickets that share the most entities with Ticket 1'
\echo '       (same customer, product, agent, etc.)'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  -- Must compare context attributes manually'
\echo '  -- No built-in structural similarity'
\echo ''
\echo 'GraphRAG Approach:'

SELECT * FROM graphrag.find_structurally_similar('Ticket', '1', 'Ticket', 1, 5);

\echo ''
\echo 'Winner: GraphRAG - Native structural similarity'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 8: LLM Context Generation
-- =============================================================================
-- Both can generate context, but GraphRAG includes relationships

\echo '============================================================'
\echo 'TEST 8: LLM Context Generation'
\echo '============================================================'
\echo 'Query: Generate context for an LLM to answer a ticket question'
\echo ''
\echo 'ContextRAG Approach:'
\echo '  SELECT contextrag.build_full_text(entity_id);'
\echo '  -- Returns: content + weighted context attributes'
\echo '  -- Example: "SSO issue... Context: customer=John Smith, product=SecureAuth"'
\echo ''
\echo 'GraphRAG Approach:'

SELECT graphrag.extract_subgraph_for_llm('Ticket', '1', 2, 10, FALSE);

\echo ''
\echo 'ContextRAG context is simpler and faster.'
\echo 'GraphRAG context is richer with relationship paths.'
\echo 'Winner: DEPENDS ON USE CASE'
\echo '  - Simple Q&A: ContextRAG (faster, sufficient)'
\echo '  - Complex analysis: GraphRAG (richer context)'
\echo '============================================================'
\echo ''

-- =============================================================================
-- TEST 9: Query Complexity / Performance
-- =============================================================================

\echo '============================================================'
\echo 'TEST 9: Query Complexity / Performance'
\echo '============================================================'
\echo ''
\echo 'ContextRAG:'
\echo '  - Single table scans with vector index'
\echo '  - Simple WHERE clauses for filtering'
\echo '  - Predictable performance O(log n) with HNSW'
\echo ''
\echo 'GraphRAG:'
\echo '  - Graph traversals can be expensive'
\echo '  - Path queries grow exponentially with hops'
\echo '  - Requires careful limit/depth constraints'
\echo ''
\echo 'Winner: ContextRAG for simple queries'
\echo '        GraphRAG for relationship-dependent queries'
\echo '============================================================'
\echo ''

-- =============================================================================
-- SUMMARY: When to Use Each Approach
-- =============================================================================

\echo '============================================================'
\echo 'SUMMARY: When to Use Each Approach'
\echo '============================================================'
\echo ''
\echo 'Use ContextRAG when:'
\echo '  - Simple semantic search is sufficient'
\echo '  - Relationships are flat (key-value metadata)'
\echo '  - Query latency is critical'
\echo '  - Data model is simple'
\echo '  - No multi-hop queries needed'
\echo ''
\echo 'Use GraphRAG when:'
\echo '  - Data has rich relationships'
\echo '  - Multi-hop discovery is valuable'
\echo '  - Path-based explanations are needed'
\echo '  - Finding structurally similar items matters'
\echo '  - Agent routing based on expertise history'
\echo '  - Customer journey analysis'
\echo ''
\echo 'Use BOTH when:'
\echo '  - Start with ContextRAG for basic RAG'
\echo '  - Add GraphRAG for relationship-heavy queries'
\echo '  - Use ContextRAG as fallback when GraphRAG is slow'
\echo '============================================================'
