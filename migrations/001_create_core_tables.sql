-- Migration 001: Create Core Tables
-- ContextRAG PostgreSQL Extension
-- Run this after installing pgvector: CREATE EXTENSION vector;

-- Create schema
CREATE SCHEMA IF NOT EXISTS contextrag;

-- Canonical entity registry with source linking
CREATE TABLE contextrag.entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    source_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    base_content JSONB NOT NULL,
    content_hash TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (source_schema, source_table, source_id)
);

COMMENT ON TABLE contextrag.entities IS 'Canonical registry of entities with source table linking';
COMMENT ON COLUMN contextrag.entities.source_schema IS 'Schema of the source table';
COMMENT ON COLUMN contextrag.entities.source_table IS 'Name of the source table';
COMMENT ON COLUMN contextrag.entities.source_id IS 'Primary key value in the source table (as text)';
COMMENT ON COLUMN contextrag.entities.entity_type IS 'Type classification (e.g., ticket, kb_article, customer)';
COMMENT ON COLUMN contextrag.entities.base_content IS 'JSONB content for embedding generation';
COMMENT ON COLUMN contextrag.entities.content_hash IS 'MD5 hash of base_content for change detection';

-- Local context attributes (key-value with weights)
CREATE TABLE contextrag.entity_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id UUID NOT NULL REFERENCES contextrag.entities(id) ON DELETE CASCADE,
    context_type TEXT NOT NULL,
    context_key TEXT NOT NULL,
    context_value TEXT NOT NULL,
    weight REAL DEFAULT 1.0,
    metadata JSONB DEFAULT '{}',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (entity_id, context_type, context_key)
);

COMMENT ON TABLE contextrag.entity_context IS 'Context attributes that enrich entities';
COMMENT ON COLUMN contextrag.entity_context.context_type IS 'Category of context (e.g., category, status, relationship)';
COMMENT ON COLUMN contextrag.entity_context.context_key IS 'Specific attribute key';
COMMENT ON COLUMN contextrag.entity_context.context_value IS 'Attribute value';
COMMENT ON COLUMN contextrag.entity_context.weight IS 'Importance weight for ranking (default 1.0)';
COMMENT ON COLUMN contextrag.entity_context.expires_at IS 'Optional expiration for temporal context';

-- Multiple embedding types per entity
CREATE TABLE contextrag.entity_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id UUID NOT NULL REFERENCES contextrag.entities(id) ON DELETE CASCADE,
    embedding_type TEXT NOT NULL,
    embedding vector(1536) NOT NULL,
    model_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (entity_id, embedding_type)
);

COMMENT ON TABLE contextrag.entity_embeddings IS 'Vector embeddings for entities';
COMMENT ON COLUMN contextrag.entity_embeddings.embedding_type IS 'Type of embedding (base, local_context)';
COMMENT ON COLUMN contextrag.entity_embeddings.embedding IS 'Vector embedding (1536 dimensions for text-embedding-3-small)';
COMMENT ON COLUMN contextrag.entity_embeddings.model_name IS 'Model used to generate the embedding';
