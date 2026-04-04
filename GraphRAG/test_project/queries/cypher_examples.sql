-- =============================================================================
-- GraphRAG: Basic Cypher Query Examples
-- =============================================================================
-- This file demonstrates basic Cypher queries on the support_graph.
-- Run after the graph has been populated with create_graph.sql.
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, support, "$user", public;

-- =============================================================================
-- SECTION 1: Basic Node Queries
-- =============================================================================

-- Count all nodes by type
\echo '=== Node counts by type ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (n)
    RETURN labels(n)[0] as node_type, COUNT(*) as count
    ORDER BY node_type
$$) AS (node_type agtype, count agtype);

-- Get all tickets with their status and priority
\echo '=== All tickets (status, priority) ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)
    RETURN t.source_id as id, t.subject as subject, t.status as status, t.priority as priority
    ORDER BY t.source_id
$$) AS (id agtype, subject agtype, status agtype, priority agtype);

-- Get all customers with their plan type
\echo '=== All customers (plan type) ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (c:Customer)
    RETURN c.name as name, c.company as company, c.plan_type as plan
    ORDER BY c.name
$$) AS (name agtype, company agtype, plan agtype);

-- =============================================================================
-- SECTION 2: Basic Relationship Queries
-- =============================================================================

-- Count all relationships by type
\echo '=== Edge counts by type ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH ()-[r]->()
    RETURN type(r) as edge_type, COUNT(*) as count
    ORDER BY edge_type
$$) AS (edge_type agtype, count agtype);

-- Get all ticket-customer relationships
\echo '=== Tickets with their customers ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:CREATED_BY]->(c:Customer)
    RETURN t.subject as ticket, c.name as customer, c.company as company
    ORDER BY t.source_id
$$) AS (ticket agtype, customer agtype, company agtype);

-- Get all ticket-agent assignments
\echo '=== Tickets with assigned agents ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ASSIGNED_TO]->(a:Agent)
    RETURN t.subject as ticket, a.name as agent, a.team as team
    ORDER BY t.source_id
$$) AS (ticket agtype, agent agtype, team agtype);

-- =============================================================================
-- SECTION 3: Multi-hop Traversals
-- =============================================================================

-- Find all tickets for enterprise customers
\echo '=== Tickets from enterprise customers ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:CREATED_BY]->(c:Customer {plan_type: 'enterprise'})
    RETURN t.subject as ticket, t.priority as priority, c.name as customer, c.company as company
    ORDER BY t.priority DESC
$$) AS (ticket agtype, priority agtype, customer agtype, company agtype);

-- Find products with the most tickets
\echo '=== Products by ticket count ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ABOUT_PRODUCT]->(p:Product)
    RETURN p.name as product, COUNT(t) as ticket_count
    ORDER BY ticket_count DESC
$$) AS (product agtype, ticket_count agtype);

-- Find agents with their assigned tickets and products
\echo '=== Agent assignments (tickets and products) ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ASSIGNED_TO]->(a:Agent),
          (t)-[:ABOUT_PRODUCT]->(p:Product)
    RETURN a.name as agent, a.team as team, t.subject as ticket, p.name as product
    ORDER BY a.name, t.source_id
$$) AS (agent agtype, team agtype, ticket agtype, product agtype);

-- =============================================================================
-- SECTION 4: Path Queries
-- =============================================================================

-- Find the path from a ticket to its KB article reference
\echo '=== Ticket to KB article paths ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:REFERENCES]->(kb:KBArticle)
    RETURN t.subject as ticket, kb.title as article
    ORDER BY t.source_id
$$) AS (ticket agtype, article agtype);

-- Find tickets and KB articles that share the same product
\echo '=== Tickets and KB articles sharing a product ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:ABOUT_PRODUCT]->(p:Product)<-[:DOCUMENTS]-(kb:KBArticle)
    RETURN t.subject as ticket, p.name as product, kb.title as related_article
    ORDER BY p.name
$$) AS (ticket agtype, product agtype, related_article agtype);

-- Find all entities connected to a specific customer (2-hop)
\echo '=== All entities within 2 hops of customer John Smith ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (c:Customer {name: 'John Smith'})-[*1..2]-(connected)
    WHERE c <> connected
    RETURN DISTINCT labels(connected)[0] as entity_type,
           CASE
               WHEN labels(connected)[0] = 'Ticket' THEN connected.subject
               WHEN labels(connected)[0] = 'Product' THEN connected.name
               WHEN labels(connected)[0] = 'Agent' THEN connected.name
               WHEN labels(connected)[0] = 'KBArticle' THEN connected.title
               ELSE connected.source_id
           END as entity_info
$$) AS (entity_type agtype, entity_info agtype);

-- =============================================================================
-- SECTION 5: Aggregation Queries
-- =============================================================================

-- Ticket statistics by status
\echo '=== Ticket statistics by status ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)
    RETURN t.status as status, COUNT(*) as count
    ORDER BY count DESC
$$) AS (status agtype, count agtype);

-- Agent workload (assigned ticket count)
\echo '=== Agent workload ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (a:Agent)
    OPTIONAL MATCH (t:Ticket)-[:ASSIGNED_TO]->(a)
    RETURN a.name as agent, a.team as team, COUNT(t) as assigned_tickets
    ORDER BY assigned_tickets DESC
$$) AS (agent agtype, team agtype, assigned_tickets agtype);

-- Customer ticket history
\echo '=== Customer ticket history ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (c:Customer)
    OPTIONAL MATCH (t:Ticket)-[:CREATED_BY]->(c)
    RETURN c.name as customer, c.plan_type as plan, COUNT(t) as ticket_count
    ORDER BY ticket_count DESC
$$) AS (customer agtype, plan agtype, ticket_count agtype);

-- =============================================================================
-- SECTION 6: Complex Pattern Matching
-- =============================================================================

-- Find tickets where the customer has enterprise plan AND high/urgent priority
\echo '=== High priority enterprise tickets ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket)-[:CREATED_BY]->(c:Customer)
    WHERE c.plan_type = 'enterprise' AND (t.priority = 'high' OR t.priority = 'urgent')
    RETURN t.subject as ticket, t.priority as priority, c.name as customer, c.company as company
$$) AS (ticket agtype, priority agtype, customer agtype, company agtype);

-- Find all messages in a conversation thread
\echo '=== Conversation thread for Ticket 1 ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[:HAS_MESSAGE]->(m:TicketMessage)
    RETURN m.sender_type as sender, m.is_internal as internal,
           substring(m.message, 0, 80) as message_preview
    ORDER BY m.source_id
$$) AS (sender agtype, internal agtype, message_preview agtype);

-- Find products without any tickets (might need attention)
\echo '=== Products without tickets ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (p:Product)
    WHERE NOT EXISTS { MATCH (t:Ticket)-[:ABOUT_PRODUCT]->(p) }
    RETURN p.name as product, p.category as category
$$) AS (product agtype, category agtype);

-- Find KB articles that could help with open tickets (same product)
\echo '=== KB articles potentially relevant to open tickets ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {status: 'open'})-[:ABOUT_PRODUCT]->(p:Product)<-[:DOCUMENTS]-(kb:KBArticle)
    WHERE NOT EXISTS { MATCH (t)-[:REFERENCES]->(kb) }
    RETURN t.subject as ticket, p.name as product, kb.title as suggested_article
$$) AS (ticket agtype, product agtype, suggested_article agtype);
