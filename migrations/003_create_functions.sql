-- Migration 003: Create Functions
-- ContextRAG PostgreSQL Extension

-- =============================================================================
-- Entity Management Functions
-- =============================================================================

-- Register or upsert an entity from source data
CREATE OR REPLACE FUNCTION contextrag.register_entity(
    p_source_schema TEXT,
    p_source_table TEXT,
    p_source_id TEXT,
    p_entity_type TEXT,
    p_base_content JSONB,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_content_hash TEXT;
BEGIN
    -- Generate content hash for change detection
    v_content_hash := md5(p_base_content::TEXT);

    INSERT INTO contextrag.entities (
        source_schema, source_table, source_id, entity_type,
        base_content, content_hash, metadata
    ) VALUES (
        p_source_schema, p_source_table, p_source_id, p_entity_type,
        p_base_content, v_content_hash, p_metadata
    )
    ON CONFLICT (source_schema, source_table, source_id) DO UPDATE SET
        entity_type = EXCLUDED.entity_type,
        base_content = EXCLUDED.base_content,
        content_hash = EXCLUDED.content_hash,
        metadata = contextrag.entities.metadata || EXCLUDED.metadata,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Add or update context attributes
CREATE OR REPLACE FUNCTION contextrag.add_context(
    p_entity_id UUID,
    p_context_type TEXT,
    p_context_key TEXT,
    p_context_value TEXT,
    p_weight REAL DEFAULT 1.0,
    p_metadata JSONB DEFAULT '{}',
    p_expires_at TIMESTAMPTZ DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO contextrag.entity_context (
        entity_id, context_type, context_key, context_value,
        weight, metadata, expires_at
    ) VALUES (
        p_entity_id, p_context_type, p_context_key, p_context_value,
        p_weight, p_metadata, p_expires_at
    )
    ON CONFLICT (entity_id, context_type, context_key) DO UPDATE SET
        context_value = EXCLUDED.context_value,
        weight = EXCLUDED.weight,
        metadata = contextrag.entity_context.metadata || EXCLUDED.metadata,
        expires_at = EXCLUDED.expires_at,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Text Building Functions
-- =============================================================================

-- Generate text from context for embedding
CREATE OR REPLACE FUNCTION contextrag.build_context_text(
    p_entity_id UUID
) RETURNS TEXT AS $$
DECLARE
    v_context_text TEXT;
BEGIN
    SELECT string_agg(
        context_type || ': ' || context_key || ' = ' || context_value,
        '; ' ORDER BY weight DESC, context_type, context_key
    )
    INTO v_context_text
    FROM contextrag.entity_context
    WHERE entity_id = p_entity_id
      AND (expires_at IS NULL OR expires_at > NOW());

    RETURN COALESCE(v_context_text, '');
END;
$$ LANGUAGE plpgsql;

-- Build full text for embedding (base content + context)
CREATE OR REPLACE FUNCTION contextrag.build_full_text(
    p_entity_id UUID
) RETURNS TEXT AS $$
DECLARE
    v_base_text TEXT;
    v_context_text TEXT;
BEGIN
    -- Get base content as text
    SELECT
        COALESCE(
            base_content->>'text',
            base_content->>'content',
            base_content->>'description',
            base_content->>'subject',
            base_content::TEXT
        )
    INTO v_base_text
    FROM contextrag.entities
    WHERE id = p_entity_id;

    -- Get context text
    v_context_text := contextrag.build_context_text(p_entity_id);

    IF v_context_text = '' THEN
        RETURN v_base_text;
    ELSE
        RETURN v_base_text || E'\n\nContext:\n' || v_context_text;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Embedding Functions
-- =============================================================================

-- Store embedding with type
CREATE OR REPLACE FUNCTION contextrag.store_embedding(
    p_entity_id UUID,
    p_embedding_type TEXT,
    p_embedding vector(1536),
    p_model_name TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO contextrag.entity_embeddings (
        entity_id, embedding_type, embedding, model_name
    ) VALUES (
        p_entity_id, p_embedding_type, p_embedding, p_model_name
    )
    ON CONFLICT (entity_id, embedding_type) DO UPDATE SET
        embedding = EXCLUDED.embedding,
        model_name = EXCLUDED.model_name,
        created_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Search Functions
-- =============================================================================

-- Basic similarity search
CREATE OR REPLACE FUNCTION contextrag.vector_search(
    p_query_embedding vector(1536),
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_entity_type TEXT DEFAULT NULL
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        (1 - (emb.embedding <=> p_query_embedding))::REAL AS similarity
    FROM contextrag.entity_embeddings emb
    JOIN contextrag.entities e ON e.id = emb.entity_id
    WHERE emb.embedding_type = p_embedding_type
      AND e.is_active = TRUE
      AND (p_entity_type IS NULL OR e.entity_type = p_entity_type)
    ORDER BY emb.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Combined base + context search with weighted scoring
CREATE OR REPLACE FUNCTION contextrag.multi_embedding_search(
    p_query_embedding vector(1536),
    p_base_weight REAL DEFAULT 0.7,
    p_context_weight REAL DEFAULT 0.3,
    p_limit INT DEFAULT 10,
    p_entity_type TEXT DEFAULT NULL
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    base_similarity REAL,
    context_similarity REAL,
    combined_score REAL
) AS $$
BEGIN
    RETURN QUERY
    WITH base_scores AS (
        SELECT
            emb.entity_id,
            (1 - (emb.embedding <=> p_query_embedding))::REAL AS similarity
        FROM contextrag.entity_embeddings emb
        WHERE emb.embedding_type = 'base'
    ),
    context_scores AS (
        SELECT
            emb.entity_id,
            (1 - (emb.embedding <=> p_query_embedding))::REAL AS similarity
        FROM contextrag.entity_embeddings emb
        WHERE emb.embedding_type = 'local_context'
    )
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        COALESCE(bs.similarity, 0::REAL) AS base_similarity,
        COALESCE(cs.similarity, 0::REAL) AS context_similarity,
        (COALESCE(bs.similarity, 0::REAL) * p_base_weight +
         COALESCE(cs.similarity, 0::REAL) * p_context_weight)::REAL AS combined_score
    FROM contextrag.entities e
    LEFT JOIN base_scores bs ON bs.entity_id = e.id
    LEFT JOIN context_scores cs ON cs.entity_id = e.id
    WHERE e.is_active = TRUE
      AND (bs.similarity IS NOT NULL OR cs.similarity IS NOT NULL)
      AND (p_entity_type IS NULL OR e.entity_type = p_entity_type)
    ORDER BY combined_score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Hybrid search: SQL filters + vector similarity
CREATE OR REPLACE FUNCTION contextrag.hybrid_search(
    p_query_embedding vector(1536),
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_entity_type TEXT DEFAULT NULL,
    p_metadata_filter JSONB DEFAULT NULL,
    p_min_similarity REAL DEFAULT 0.0
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    metadata JSONB,
    similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        e.metadata,
        (1 - (emb.embedding <=> p_query_embedding))::REAL AS similarity
    FROM contextrag.entity_embeddings emb
    JOIN contextrag.entities e ON e.id = emb.entity_id
    WHERE emb.embedding_type = p_embedding_type
      AND e.is_active = TRUE
      AND (p_entity_type IS NULL OR e.entity_type = p_entity_type)
      AND (p_metadata_filter IS NULL OR e.metadata @> p_metadata_filter)
      AND (1 - (emb.embedding <=> p_query_embedding))::REAL >= p_min_similarity
    ORDER BY emb.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Context-aware search: vector search with context filtering
CREATE OR REPLACE FUNCTION contextrag.context_aware_search(
    p_query_embedding vector(1536),
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_entity_type TEXT DEFAULT NULL,
    p_context_type TEXT DEFAULT NULL,
    p_context_key TEXT DEFAULT NULL,
    p_context_value TEXT DEFAULT NULL
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    context_matches JSONB,
    similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    WITH matched_entities AS (
        SELECT DISTINCT ec.entity_id
        FROM contextrag.entity_context ec
        WHERE (p_context_type IS NULL OR ec.context_type = p_context_type)
          AND (p_context_key IS NULL OR ec.context_key = p_context_key)
          AND (p_context_value IS NULL OR ec.context_value = p_context_value)
          AND (ec.expires_at IS NULL OR ec.expires_at > NOW())
    ),
    entity_contexts AS (
        SELECT
            ec.entity_id,
            jsonb_agg(jsonb_build_object(
                'type', ec.context_type,
                'key', ec.context_key,
                'value', ec.context_value,
                'weight', ec.weight
            )) AS contexts
        FROM contextrag.entity_context ec
        WHERE (ec.expires_at IS NULL OR ec.expires_at > NOW())
        GROUP BY ec.entity_id
    )
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        COALESCE(ectx.contexts, '[]'::JSONB) AS context_matches,
        (1 - (emb.embedding <=> p_query_embedding))::REAL AS similarity
    FROM contextrag.entity_embeddings emb
    JOIN contextrag.entities e ON e.id = emb.entity_id
    LEFT JOIN entity_contexts ectx ON ectx.entity_id = e.id
    WHERE emb.embedding_type = p_embedding_type
      AND e.is_active = TRUE
      AND (p_entity_type IS NULL OR e.entity_type = p_entity_type)
      AND (
          (p_context_type IS NULL AND p_context_key IS NULL AND p_context_value IS NULL)
          OR e.id IN (SELECT me.entity_id FROM matched_entities me)
      )
    ORDER BY emb.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Maintenance Functions
-- =============================================================================

-- Find entities needing re-embedding
CREATE OR REPLACE FUNCTION contextrag.get_stale_entities(
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 100
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    entity_updated_at TIMESTAMPTZ,
    embedding_created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        e.updated_at AS entity_updated_at,
        emb.created_at AS embedding_created_at
    FROM contextrag.entities e
    LEFT JOIN contextrag.entity_embeddings emb
        ON emb.entity_id = e.id AND emb.embedding_type = p_embedding_type
    WHERE e.is_active = TRUE
      AND (emb.id IS NULL OR emb.created_at < e.updated_at)
    ORDER BY e.updated_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Get entities without embeddings
CREATE OR REPLACE FUNCTION contextrag.get_unembedded_entities(
    p_embedding_type TEXT DEFAULT 'base',
    p_entity_type TEXT DEFAULT NULL,
    p_limit INT DEFAULT 100
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    full_text TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        CASE
            WHEN p_embedding_type = 'local_context' THEN contextrag.build_full_text(e.id)
            ELSE COALESCE(
                e.base_content->>'text',
                e.base_content->>'content',
                e.base_content->>'description',
                e.base_content->>'subject',
                e.base_content::TEXT
            )
        END AS full_text
    FROM contextrag.entities e
    LEFT JOIN contextrag.entity_embeddings emb
        ON emb.entity_id = e.id AND emb.embedding_type = p_embedding_type
    WHERE e.is_active = TRUE
      AND emb.id IS NULL
      AND (p_entity_type IS NULL OR e.entity_type = p_entity_type)
    ORDER BY e.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Extension statistics
CREATE OR REPLACE FUNCTION contextrag.get_stats()
RETURNS TABLE (
    metric TEXT,
    value BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'total_entities'::TEXT, COUNT(*)::BIGINT FROM contextrag.entities
    UNION ALL
    SELECT 'active_entities'::TEXT, COUNT(*)::BIGINT FROM contextrag.entities WHERE is_active = TRUE
    UNION ALL
    SELECT 'total_context_entries'::TEXT, COUNT(*)::BIGINT FROM contextrag.entity_context
    UNION ALL
    SELECT 'total_embeddings'::TEXT, COUNT(*)::BIGINT FROM contextrag.entity_embeddings
    UNION ALL
    SELECT 'base_embeddings'::TEXT, COUNT(*)::BIGINT FROM contextrag.entity_embeddings WHERE embedding_type = 'base'
    UNION ALL
    SELECT 'local_context_embeddings'::TEXT, COUNT(*)::BIGINT FROM contextrag.entity_embeddings WHERE embedding_type = 'local_context'
    UNION ALL
    SELECT 'distinct_entity_types'::TEXT, COUNT(DISTINCT entity_type)::BIGINT FROM contextrag.entities
    UNION ALL
    SELECT 'distinct_context_types'::TEXT, COUNT(DISTINCT context_type)::BIGINT FROM contextrag.entity_context;
END;
$$ LANGUAGE plpgsql;

-- Get entity details
CREATE OR REPLACE FUNCTION contextrag.get_entity_details(
    p_entity_id UUID
) RETURNS TABLE (
    entity_id UUID,
    source_schema TEXT,
    source_table TEXT,
    source_id TEXT,
    entity_type TEXT,
    base_content JSONB,
    metadata JSONB,
    contexts JSONB,
    embedding_types TEXT[],
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id AS entity_id,
        e.source_schema,
        e.source_table,
        e.source_id,
        e.entity_type,
        e.base_content,
        e.metadata,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'type', ec.context_type,
                'key', ec.context_key,
                'value', ec.context_value,
                'weight', ec.weight
            ))
            FROM contextrag.entity_context ec
            WHERE ec.entity_id = e.id),
            '[]'::JSONB
        ) AS contexts,
        COALESCE(
            (SELECT array_agg(DISTINCT emb.embedding_type)
            FROM contextrag.entity_embeddings emb
            WHERE emb.entity_id = e.id),
            ARRAY[]::TEXT[]
        ) AS embedding_types,
        e.created_at,
        e.updated_at
    FROM contextrag.entities e
    WHERE e.id = p_entity_id;
END;
$$ LANGUAGE plpgsql;

-- Deactivate an entity
CREATE OR REPLACE FUNCTION contextrag.deactivate_entity(
    p_entity_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE contextrag.entities
    SET is_active = FALSE, updated_at = NOW()
    WHERE id = p_entity_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Reactivate an entity
CREATE OR REPLACE FUNCTION contextrag.reactivate_entity(
    p_entity_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE contextrag.entities
    SET is_active = TRUE, updated_at = NOW()
    WHERE id = p_entity_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Clean up expired context entries
CREATE OR REPLACE FUNCTION contextrag.cleanup_expired_context()
RETURNS BIGINT AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    DELETE FROM contextrag.entity_context
    WHERE expires_at IS NOT NULL AND expires_at <= NOW();

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;
