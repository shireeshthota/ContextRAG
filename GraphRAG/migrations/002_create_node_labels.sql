-- =============================================================================
-- GraphRAG Migration 002: Create Node Labels (Vertex Types)
-- =============================================================================
-- This migration creates all node labels (vertex types) for the support graph.
-- Each node type represents an entity from the relational CRM schema.
--
-- Node Types:
-- - Ticket: Support tickets
-- - Customer: Customer records
-- - Product: Product catalog
-- - Agent: Support agents
-- - KBArticle: Knowledge base articles
-- - TicketMessage: Messages on tickets
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, "$user", public;

-- =============================================================================
-- Create Node Labels
-- =============================================================================
-- In AGE, we create vertex labels using Cypher CREATE statements.
-- Each label can then hold vertices with properties.

-- Create Ticket node label
SELECT create_vlabel('support_graph', 'Ticket');

-- Create Customer node label
SELECT create_vlabel('support_graph', 'Customer');

-- Create Product node label
SELECT create_vlabel('support_graph', 'Product');

-- Create Agent node label
SELECT create_vlabel('support_graph', 'Agent');

-- Create KBArticle node label
SELECT create_vlabel('support_graph', 'KBArticle');

-- Create TicketMessage node label
SELECT create_vlabel('support_graph', 'TicketMessage');

-- =============================================================================
-- Node Label Properties Reference
-- =============================================================================
-- Properties are defined when nodes are created. Here's the expected schema:
--
-- Ticket:
--   - source_id (INT): Links to support.tickets.id
--   - subject (TEXT): Ticket subject line
--   - description (TEXT): Full ticket description
--   - status (TEXT): open, in_progress, waiting, resolved, closed
--   - priority (TEXT): low, medium, high, urgent
--   - category (TEXT): billing, technical, feature_request, bug, general
--
-- Customer:
--   - source_id (INT): Links to support.customers.id
--   - email (TEXT): Customer email
--   - name (TEXT): Customer name
--   - company (TEXT): Company name
--   - plan_type (TEXT): free, pro, enterprise
--
-- Product:
--   - source_id (INT): Links to support.products.id
--   - name (TEXT): Product name
--   - category (TEXT): software, hardware, service
--   - description (TEXT): Product description
--
-- Agent:
--   - source_id (INT): Links to support.agents.id
--   - email (TEXT): Agent email
--   - name (TEXT): Agent name
--   - team (TEXT): billing, technical, general
--
-- KBArticle:
--   - source_id (INT): Links to support.kb_articles.id
--   - title (TEXT): Article title
--   - content (TEXT): Article content
--   - category (TEXT): getting_started, troubleshooting, faq, how_to
--   - tags (TEXT[]): Array of tags
--
-- TicketMessage:
--   - source_id (INT): Links to support.ticket_messages.id
--   - message (TEXT): Message content
--   - sender_type (TEXT): customer, agent, system
--   - is_internal (BOOLEAN): Internal note flag
-- =============================================================================

-- =============================================================================
-- Verification Queries
-- =============================================================================
-- List all vertex labels in the graph:
-- SELECT * FROM ag_catalog.ag_label
-- WHERE graph = (SELECT graphid FROM ag_catalog.ag_graph WHERE name = 'support_graph')
-- AND kind = 'v';
--
-- Expected output: 6 labels (Ticket, Customer, Product, Agent, KBArticle, TicketMessage)
-- =============================================================================
