-- Register Entities with ContextRAG
-- Run after seed_data.sql

-- =============================================================================
-- Register Support Tickets as Entities
-- =============================================================================

-- Register each ticket with its content
DO $$
DECLARE
    t RECORD;
    v_entity_id UUID;
BEGIN
    FOR t IN
        SELECT
            tk.id,
            tk.subject,
            tk.description,
            tk.status,
            tk.priority,
            tk.category,
            c.name AS customer_name,
            c.company AS customer_company,
            c.plan_type AS customer_plan,
            p.name AS product_name,
            a.name AS agent_name,
            a.team AS agent_team
        FROM support.tickets tk
        JOIN support.customers c ON c.id = tk.customer_id
        LEFT JOIN support.products p ON p.id = tk.product_id
        LEFT JOIN support.agents a ON a.id = tk.agent_id
    LOOP
        -- Register the ticket entity
        v_entity_id := contextrag.register_entity(
            'support',
            'tickets',
            t.id::TEXT,
            'ticket',
            jsonb_build_object(
                'subject', t.subject,
                'description', t.description,
                'text', t.subject || '. ' || t.description
            ),
            jsonb_build_object(
                'product', t.product_name,
                'customer_plan', t.customer_plan
            )
        );

        -- Add status context
        PERFORM contextrag.add_context(
            v_entity_id,
            'status',
            'ticket_status',
            t.status,
            CASE t.status
                WHEN 'open' THEN 1.0
                WHEN 'in_progress' THEN 0.9
                WHEN 'waiting' THEN 0.7
                WHEN 'resolved' THEN 0.5
                WHEN 'closed' THEN 0.3
            END
        );

        -- Add priority context
        PERFORM contextrag.add_context(
            v_entity_id,
            'priority',
            'ticket_priority',
            t.priority,
            CASE t.priority
                WHEN 'urgent' THEN 1.0
                WHEN 'high' THEN 0.8
                WHEN 'medium' THEN 0.5
                WHEN 'low' THEN 0.3
            END
        );

        -- Add category context
        IF t.category IS NOT NULL THEN
            PERFORM contextrag.add_context(
                v_entity_id,
                'category',
                'ticket_category',
                t.category,
                1.0
            );
        END IF;

        -- Add customer context
        PERFORM contextrag.add_context(
            v_entity_id,
            'customer',
            'customer_name',
            t.customer_name,
            0.7
        );

        IF t.customer_company IS NOT NULL THEN
            PERFORM contextrag.add_context(
                v_entity_id,
                'customer',
                'customer_company',
                t.customer_company,
                0.6
            );
        END IF;

        PERFORM contextrag.add_context(
            v_entity_id,
            'customer',
            'plan_type',
            t.customer_plan,
            0.8
        );

        -- Add product context
        IF t.product_name IS NOT NULL THEN
            PERFORM contextrag.add_context(
                v_entity_id,
                'product',
                'product_name',
                t.product_name,
                0.9
            );
        END IF;

        -- Add agent context
        IF t.agent_name IS NOT NULL THEN
            PERFORM contextrag.add_context(
                v_entity_id,
                'agent',
                'assigned_agent',
                t.agent_name,
                0.5
            );
            PERFORM contextrag.add_context(
                v_entity_id,
                'agent',
                'agent_team',
                t.agent_team,
                0.6
            );
        END IF;

        RAISE NOTICE 'Registered ticket % with entity_id %', t.id, v_entity_id;
    END LOOP;
END $$;

-- =============================================================================
-- Register KB Articles as Entities
-- =============================================================================

DO $$
DECLARE
    a RECORD;
    v_entity_id UUID;
    v_tag TEXT;
BEGIN
    FOR a IN
        SELECT
            kb.id,
            kb.title,
            kb.content,
            kb.category,
            kb.tags,
            p.name AS product_name
        FROM support.kb_articles kb
        LEFT JOIN support.products p ON p.id = kb.product_id
        WHERE kb.is_published = TRUE
    LOOP
        -- Register the KB article entity
        v_entity_id := contextrag.register_entity(
            'support',
            'kb_articles',
            a.id::TEXT,
            'kb_article',
            jsonb_build_object(
                'title', a.title,
                'content', a.content,
                'text', a.title || '. ' || a.content
            ),
            jsonb_build_object(
                'product', a.product_name
            )
        );

        -- Add category context
        PERFORM contextrag.add_context(
            v_entity_id,
            'category',
            'article_category',
            a.category,
            1.0
        );

        -- Add product context
        IF a.product_name IS NOT NULL THEN
            PERFORM contextrag.add_context(
                v_entity_id,
                'product',
                'product_name',
                a.product_name,
                0.9
            );
        END IF;

        -- Add tag contexts
        IF a.tags IS NOT NULL THEN
            FOREACH v_tag IN ARRAY a.tags
            LOOP
                PERFORM contextrag.add_context(
                    v_entity_id,
                    'tag',
                    v_tag,
                    v_tag,
                    0.7
                );
            END LOOP;
        END IF;

        RAISE NOTICE 'Registered KB article % with entity_id %', a.id, v_entity_id;
    END LOOP;
END $$;

-- =============================================================================
-- Verification
-- =============================================================================

-- Show registered entities
SELECT
    e.entity_type,
    e.source_table,
    e.source_id,
    e.base_content->>'subject' AS subject,
    e.base_content->>'title' AS title,
    (SELECT COUNT(*) FROM contextrag.entity_context ec WHERE ec.entity_id = e.id) AS context_count
FROM contextrag.entities e
ORDER BY e.entity_type, e.source_id::INT;

-- Show context breakdown by entity
SELECT
    e.entity_type,
    e.source_id,
    ec.context_type,
    ec.context_key,
    ec.context_value,
    ec.weight
FROM contextrag.entities e
JOIN contextrag.entity_context ec ON ec.entity_id = e.id
ORDER BY e.entity_type, e.source_id::INT, ec.context_type, ec.context_key;

-- Show stats
SELECT * FROM contextrag.get_stats();
