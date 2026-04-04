-- =============================================================================
-- GraphRAG Migration 003: Create Edge Labels (Relationship Types)
-- =============================================================================
-- This migration creates all edge labels (relationship types) for the support graph.
-- Edges represent relationships between entities, derived from foreign keys
-- and semantic connections.
--
-- Edge Types:
-- Foreign Key Relationships:
-- - CREATED_BY: Ticket -> Customer
-- - ASSIGNED_TO: Ticket -> Agent
-- - ABOUT_PRODUCT: Ticket -> Product
-- - HAS_MESSAGE: Ticket -> TicketMessage
-- - DOCUMENTS: KBArticle -> Product
--
-- Semantic/Derived Relationships:
-- - SIMILAR_TO: Ticket -> Ticket (semantic similarity)
-- - KB_SIMILAR_TO: KBArticle -> KBArticle (similar articles)
-- - REFERENCES: Ticket -> KBArticle (ticket mentions article)
-- - RESOLVED_USING: Ticket -> KBArticle (used to resolve ticket)
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, "$user", public;

-- =============================================================================
-- Create Edge Labels - Foreign Key Relationships
-- =============================================================================

-- CREATED_BY: Links a ticket to the customer who created it
-- Direction: (Ticket)-[:CREATED_BY]->(Customer)
SELECT create_elabel('support_graph', 'CREATED_BY');

-- ASSIGNED_TO: Links a ticket to the agent handling it
-- Direction: (Ticket)-[:ASSIGNED_TO]->(Agent)
SELECT create_elabel('support_graph', 'ASSIGNED_TO');

-- ABOUT_PRODUCT: Links a ticket to the product it concerns
-- Direction: (Ticket)-[:ABOUT_PRODUCT]->(Product)
SELECT create_elabel('support_graph', 'ABOUT_PRODUCT');

-- HAS_MESSAGE: Links a ticket to its messages
-- Direction: (Ticket)-[:HAS_MESSAGE]->(TicketMessage)
SELECT create_elabel('support_graph', 'HAS_MESSAGE');

-- DOCUMENTS: Links a KB article to the product it documents
-- Direction: (KBArticle)-[:DOCUMENTS]->(Product)
SELECT create_elabel('support_graph', 'DOCUMENTS');

-- =============================================================================
-- Create Edge Labels - Semantic Relationships
-- =============================================================================

-- SIMILAR_TO: Links semantically similar tickets
-- Direction: (Ticket)-[:SIMILAR_TO {score: 0.85}]->(Ticket)
-- Properties:
--   - score (FLOAT): Similarity score from vector comparison
--   - computed_at (TIMESTAMP): When similarity was computed
SELECT create_elabel('support_graph', 'SIMILAR_TO');

-- KB_SIMILAR_TO: Links semantically similar KB articles
-- Direction: (KBArticle)-[:KB_SIMILAR_TO {score: 0.9}]->(KBArticle)
-- Properties:
--   - score (FLOAT): Similarity score
SELECT create_elabel('support_graph', 'KB_SIMILAR_TO');

-- REFERENCES: Ticket references or is related to a KB article
-- Direction: (Ticket)-[:REFERENCES]->(KBArticle)
-- This can be created when a ticket mentions article keywords
SELECT create_elabel('support_graph', 'REFERENCES');

-- RESOLVED_USING: A ticket was resolved using a specific KB article
-- Direction: (Ticket)-[:RESOLVED_USING]->(KBArticle)
-- Properties:
--   - resolved_at (TIMESTAMP): When resolution occurred
SELECT create_elabel('support_graph', 'RESOLVED_USING');

-- =============================================================================
-- Edge Label Properties Reference
-- =============================================================================
-- Edge properties are defined when edges are created. Common patterns:
--
-- Structural edges (from foreign keys):
--   - created_at (TIMESTAMP): When the edge was created in graph
--
-- Similarity edges:
--   - score (FLOAT): Similarity score (0.0 to 1.0)
--   - computed_at (TIMESTAMP): When similarity was computed
--   - method (TEXT): How similarity was computed (e.g., 'cosine', 'jaccard')
--
-- Resolution edges:
--   - resolved_at (TIMESTAMP): When ticket was resolved
--   - helpful (BOOLEAN): Whether the article was marked helpful
-- =============================================================================

-- =============================================================================
-- Verification Queries
-- =============================================================================
-- List all edge labels in the graph:
-- SELECT * FROM ag_catalog.ag_label
-- WHERE graph = (SELECT graphid FROM ag_catalog.ag_graph WHERE name = 'support_graph')
-- AND kind = 'e';
--
-- Expected output: 9 labels (CREATED_BY, ASSIGNED_TO, ABOUT_PRODUCT, HAS_MESSAGE,
--                           DOCUMENTS, SIMILAR_TO, KB_SIMILAR_TO, REFERENCES, RESOLVED_USING)
-- =============================================================================
