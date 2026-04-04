-- =============================================================================
-- GraphRAG: Convert Relational Data to Graph
-- =============================================================================
-- This script converts data from the relational support schema into the
-- AGE property graph. Run after:
-- 1. Support schema created (support_tickets.sql)
-- 2. Seed data loaded (seed_data.sql)
-- 3. GraphRAG extension installed
--
-- Graph Structure:
-- - Nodes: Ticket, Customer, Product, Agent, KBArticle, TicketMessage
-- - Edges: CREATED_BY, ASSIGNED_TO, ABOUT_PRODUCT, HAS_MESSAGE, DOCUMENTS, etc.
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, support, "$user", public;

-- =============================================================================
-- CREATE GRAPH (if not exists)
-- =============================================================================
-- Note: We need to check if graph exists first to avoid errors
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'support_graph') THEN
        PERFORM create_graph('support_graph');
    END IF;
END $$;

-- =============================================================================
-- CREATE NODE LABELS (if not exist)
-- =============================================================================
DO $$
DECLARE
    v_graphid OID;
BEGIN
    SELECT graphid INTO v_graphid FROM ag_catalog.ag_graph WHERE name = 'support_graph';

    -- Create vertex labels if they don't exist
    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'Ticket' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'Ticket');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'Customer' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'Customer');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'Product' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'Product');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'Agent' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'Agent');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'KBArticle' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'KBArticle');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'TicketMessage' AND graph = v_graphid) THEN
        PERFORM create_vlabel('support_graph', 'TicketMessage');
    END IF;
END $$;

-- =============================================================================
-- CREATE EDGE LABELS (if not exist)
-- =============================================================================
DO $$
DECLARE
    v_graphid OID;
BEGIN
    SELECT graphid INTO v_graphid FROM ag_catalog.ag_graph WHERE name = 'support_graph';

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'CREATED_BY' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'CREATED_BY');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'ASSIGNED_TO' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'ASSIGNED_TO');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'ABOUT_PRODUCT' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'ABOUT_PRODUCT');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'HAS_MESSAGE' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'HAS_MESSAGE');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'DOCUMENTS' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'DOCUMENTS');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'SIMILAR_TO' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'SIMILAR_TO');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'KB_SIMILAR_TO' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'KB_SIMILAR_TO');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'REFERENCES' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'REFERENCES');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ag_catalog.ag_label WHERE name = 'RESOLVED_USING' AND graph = v_graphid) THEN
        PERFORM create_elabel('support_graph', 'RESOLVED_USING');
    END IF;
END $$;

-- =============================================================================
-- CREATE NODES: Products
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.products
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (p:Product {source_id: %L})
            SET p.name = %L,
                p.category = %L,
                p.description = %L,
                p.is_active = %L
        $cypher$,
            rec.id::TEXT,
            rec.name,
            rec.category,
            COALESCE(rec.description, ''),
            rec.is_active
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE NODES: Customers
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.customers
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (c:Customer {source_id: %L})
            SET c.email = %L,
                c.name = %L,
                c.company = %L,
                c.plan_type = %L
        $cypher$,
            rec.id::TEXT,
            rec.email,
            rec.name,
            COALESCE(rec.company, ''),
            rec.plan_type
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE NODES: Agents
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.agents
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (a:Agent {source_id: %L})
            SET a.email = %L,
                a.name = %L,
                a.team = %L,
                a.is_available = %L
        $cypher$,
            rec.id::TEXT,
            rec.email,
            rec.name,
            COALESCE(rec.team, ''),
            rec.is_available
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE NODES: Tickets
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.tickets
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (t:Ticket {source_id: %L})
            SET t.subject = %L,
                t.description = %L,
                t.status = %L,
                t.priority = %L,
                t.category = %L,
                t.customer_id = %L,
                t.agent_id = %L,
                t.product_id = %L
        $cypher$,
            rec.id::TEXT,
            rec.subject,
            rec.description,
            rec.status,
            rec.priority,
            COALESCE(rec.category, ''),
            rec.customer_id::TEXT,
            COALESCE(rec.agent_id::TEXT, ''),
            COALESCE(rec.product_id::TEXT, '')
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE NODES: KB Articles
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.kb_articles
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (kb:KBArticle {source_id: %L})
            SET kb.title = %L,
                kb.content = %L,
                kb.category = %L,
                kb.tags = %L,
                kb.product_id = %L,
                kb.is_published = %L
        $cypher$,
            rec.id::TEXT,
            rec.title,
            rec.content,
            rec.category,
            array_to_string(COALESCE(rec.tags, ARRAY[]::TEXT[]), ','),
            COALESCE(rec.product_id::TEXT, ''),
            rec.is_published
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE NODES: Ticket Messages
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM support.ticket_messages
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MERGE (m:TicketMessage {source_id: %L})
            SET m.message = %L,
                m.sender_type = %L,
                m.sender_id = %L,
                m.is_internal = %L,
                m.ticket_id = %L
        $cypher$,
            rec.id::TEXT,
            rec.message,
            rec.sender_type,
            COALESCE(rec.sender_id::TEXT, ''),
            rec.is_internal,
            rec.ticket_id::TEXT
        )) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE EDGES: Ticket -> Customer (CREATED_BY)
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id, customer_id FROM support.tickets WHERE customer_id IS NOT NULL
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (t:Ticket {source_id: %L}), (c:Customer {source_id: %L})
            MERGE (t)-[:CREATED_BY]->(c)
        $cypher$, rec.id::TEXT, rec.customer_id::TEXT)) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE EDGES: Ticket -> Agent (ASSIGNED_TO)
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id, agent_id FROM support.tickets WHERE agent_id IS NOT NULL
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (t:Ticket {source_id: %L}), (a:Agent {source_id: %L})
            MERGE (t)-[:ASSIGNED_TO]->(a)
        $cypher$, rec.id::TEXT, rec.agent_id::TEXT)) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE EDGES: Ticket -> Product (ABOUT_PRODUCT)
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id, product_id FROM support.tickets WHERE product_id IS NOT NULL
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (t:Ticket {source_id: %L}), (p:Product {source_id: %L})
            MERGE (t)-[:ABOUT_PRODUCT]->(p)
        $cypher$, rec.id::TEXT, rec.product_id::TEXT)) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE EDGES: Ticket -> TicketMessage (HAS_MESSAGE)
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id, ticket_id FROM support.ticket_messages
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (t:Ticket {source_id: %L}), (m:TicketMessage {source_id: %L})
            MERGE (t)-[:HAS_MESSAGE]->(m)
        $cypher$, rec.ticket_id::TEXT, rec.id::TEXT)) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE EDGES: KBArticle -> Product (DOCUMENTS)
-- =============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT id, product_id FROM support.kb_articles WHERE product_id IS NOT NULL
    LOOP
        PERFORM * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (kb:KBArticle {source_id: %L}), (p:Product {source_id: %L})
            MERGE (kb)-[:DOCUMENTS]->(p)
        $cypher$, rec.id::TEXT, rec.product_id::TEXT)) AS (result agtype);
    END LOOP;
END $$;

-- =============================================================================
-- CREATE SEMANTIC EDGES: REFERENCES (Ticket -> KBArticle)
-- =============================================================================
-- Based on keyword matching between tickets and KB articles
-- In production, this would be based on embeddings or more sophisticated NLP

-- Ticket 1 (SSO issue) references KB Article 1 (SSO with Azure AD)
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'}), (kb:KBArticle {source_id: '1'})
    MERGE (t)-[:REFERENCES {reason: 'SSO authentication topic match'}]->(kb)
$$) AS (result agtype);

-- Ticket 4 (Sync issue) references KB Article 2 (Sync troubleshooting)
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '4'}), (kb:KBArticle {source_id: '2'})
    MERGE (t)-[:REFERENCES {reason: 'CloudSync sync issue match'}]->(kb)
$$) AS (result agtype);

-- Ticket 5 (API rate limit) references KB Article 3 (API rate limits)
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '5'}), (kb:KBArticle {source_id: '3'})
    MERGE (t)-[:REFERENCES {reason: 'API rate limit topic match'}]->(kb)
$$) AS (result agtype);

-- Ticket 6 (Password reset) references KB Article 4 (Password reset)
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '6'}), (kb:KBArticle {source_id: '4'})
    MERGE (t)-[:REFERENCES {reason: 'Password reset topic match'}]->(kb)
$$) AS (result agtype);

-- =============================================================================
-- CREATE SEMANTIC EDGES: RESOLVED_USING (resolved Ticket -> KBArticle)
-- =============================================================================
-- Ticket 7 (resolved billing) - no direct KB match, but could reference billing FAQ

-- =============================================================================
-- VERIFICATION: Count nodes and edges
-- =============================================================================
\echo '=== Graph Population Summary ==='
\echo ''
\echo 'Node counts:'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (n)
    RETURN labels(n)[0] as node_type, COUNT(*) as count
    ORDER BY node_type
$$) AS (node_type agtype, count agtype);

\echo ''
\echo 'Edge counts:'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH ()-[r]->()
    RETURN type(r) as edge_type, COUNT(*) as count
    ORDER BY edge_type
$$) AS (edge_type agtype, count agtype);

\echo ''
\echo 'Total nodes and edges:'
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (n)
    WITH COUNT(n) as nodes
    MATCH ()-[r]->()
    RETURN nodes, COUNT(r) as edges
$$) AS (nodes agtype, edges agtype);

-- =============================================================================
-- Sample Queries to Verify Graph Structure
-- =============================================================================
\echo ''
\echo '=== Sample: Ticket 1 with all relationships ==='
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[r]-(connected)
    RETURN t.subject as ticket_subject,
           type(r) as relationship,
           labels(connected)[0] as connected_type,
           CASE
               WHEN labels(connected)[0] = 'Customer' THEN connected.name
               WHEN labels(connected)[0] = 'Agent' THEN connected.name
               WHEN labels(connected)[0] = 'Product' THEN connected.name
               WHEN labels(connected)[0] = 'KBArticle' THEN connected.title
               WHEN labels(connected)[0] = 'TicketMessage' THEN substring(connected.message, 0, 50)
               ELSE connected.source_id
           END as connected_info
$$) AS (ticket_subject agtype, relationship agtype, connected_type agtype, connected_info agtype);
