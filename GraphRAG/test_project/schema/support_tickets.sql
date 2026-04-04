-- Test Project Schema: Support Ticket System
-- Demonstrates GraphRAG with a CRM-style application
-- Same schema as ContextRAG for comparison

-- Create schema
CREATE SCHEMA IF NOT EXISTS support;

-- =============================================================================
-- Customer Records
-- =============================================================================
CREATE TABLE support.customers (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    company TEXT,
    plan_type TEXT DEFAULT 'free',  -- free, pro, enterprise
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Product Catalog
-- =============================================================================
CREATE TABLE support.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,  -- software, hardware, service
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Support Agents
-- =============================================================================
CREATE TABLE support.agents (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    team TEXT,  -- billing, technical, general
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Support Tickets (Main Entity)
-- =============================================================================
CREATE TABLE support.tickets (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES support.customers(id),
    agent_id INT REFERENCES support.agents(id),
    product_id INT REFERENCES support.products(id),
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT DEFAULT 'open',  -- open, in_progress, waiting, resolved, closed
    priority TEXT DEFAULT 'medium',  -- low, medium, high, urgent
    category TEXT,  -- billing, technical, feature_request, bug, general
    resolution TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- =============================================================================
-- Ticket Messages
-- =============================================================================
CREATE TABLE support.ticket_messages (
    id SERIAL PRIMARY KEY,
    ticket_id INT REFERENCES support.tickets(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL,  -- customer, agent, system
    sender_id INT,  -- customer_id or agent_id
    message TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT FALSE,  -- internal notes not visible to customer
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Knowledge Base Articles
-- =============================================================================
CREATE TABLE support.kb_articles (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL,  -- getting_started, troubleshooting, faq, how_to
    tags TEXT[],
    product_id INT REFERENCES support.products(id),
    is_published BOOLEAN DEFAULT TRUE,
    view_count INT DEFAULT 0,
    helpful_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Indexes for Performance
-- =============================================================================
CREATE INDEX idx_tickets_customer ON support.tickets(customer_id);
CREATE INDEX idx_tickets_agent ON support.tickets(agent_id);
CREATE INDEX idx_tickets_status ON support.tickets(status);
CREATE INDEX idx_tickets_priority ON support.tickets(priority);
CREATE INDEX idx_tickets_created ON support.tickets(created_at);
CREATE INDEX idx_ticket_messages_ticket ON support.ticket_messages(ticket_id);
CREATE INDEX idx_kb_articles_category ON support.kb_articles(category);
CREATE INDEX idx_kb_articles_product ON support.kb_articles(product_id);
CREATE INDEX idx_kb_articles_tags ON support.kb_articles USING GIN (tags);
