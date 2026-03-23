-- Migration 002: Create Indexes
-- ContextRAG PostgreSQL Extension

-- =============================================================================
-- Entity Indexes
-- =============================================================================

-- B-tree indexes on source columns for lookups
CREATE INDEX IF NOT EXISTS idx_entities_source
    ON contextrag.entities(source_schema, source_table, source_id);

-- Entity type for filtering
CREATE INDEX IF NOT EXISTS idx_entities_type
    ON contextrag.entities(entity_type);

-- Active entities (partial index for common filter)
CREATE INDEX IF NOT EXISTS idx_entities_active
    ON contextrag.entities(is_active)
    WHERE is_active = TRUE;

-- Updated timestamp for finding stale entities
CREATE INDEX IF NOT EXISTS idx_entities_updated
    ON contextrag.entities(updated_at);

-- GIN index on metadata JSONB for flexible filtering
CREATE INDEX IF NOT EXISTS idx_entities_metadata
    ON contextrag.entities USING GIN (metadata);

-- =============================================================================
-- Entity Context Indexes
-- =============================================================================

-- Fast lookup by entity
CREATE INDEX IF NOT EXISTS idx_entity_context_entity
    ON contextrag.entity_context(entity_id);

-- Filter by context type
CREATE INDEX IF NOT EXISTS idx_entity_context_type
    ON contextrag.entity_context(context_type);

-- Find expiring context (partial index)
CREATE INDEX IF NOT EXISTS idx_entity_context_expires
    ON contextrag.entity_context(expires_at)
    WHERE expires_at IS NOT NULL;

-- =============================================================================
-- Embedding Indexes (HNSW for Vector Search)
-- =============================================================================

-- Separate HNSW index for 'base' embeddings
-- This ensures semantic separation and optimal performance
CREATE INDEX IF NOT EXISTS idx_embeddings_base_hnsw
    ON contextrag.entity_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE embedding_type = 'base';

-- Separate HNSW index for 'local_context' embeddings
CREATE INDEX IF NOT EXISTS idx_embeddings_local_context_hnsw
    ON contextrag.entity_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE embedding_type = 'local_context';

-- B-tree indexes for non-vector queries
CREATE INDEX IF NOT EXISTS idx_embeddings_entity
    ON contextrag.entity_embeddings(entity_id);

CREATE INDEX IF NOT EXISTS idx_embeddings_type
    ON contextrag.entity_embeddings(embedding_type);
