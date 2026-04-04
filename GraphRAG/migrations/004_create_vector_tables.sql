-- =============================================================================
-- GraphRAG Migration 004: Create Vector Tables
-- =============================================================================
-- This migration creates tables for storing embeddings and caches for
-- graph-enhanced RAG operations.
--
-- Tables:
-- - node_embeddings: Vector embeddings for graph nodes
-- - subgraph_cache: Cached subgraph extractions for LLM context
-- - graph_stats: Statistics for monitoring graph health
-- =============================================================================

-- Ensure pgvector extension is installed
CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================================
-- Node Embeddings Table
-- =============================================================================
-- Stores vector embeddings for each graph node, supporting multiple
-- embedding types (base content vs. neighborhood-aware).

CREATE TABLE graphrag.node_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Graph node reference
    -- Note: AGE uses internal IDs, but we store source_id for easier lookup
    node_label TEXT NOT NULL,           -- 'Ticket', 'Customer', 'KBArticle', etc.
    source_id TEXT NOT NULL,            -- Original table ID (e.g., '1', '2')

    -- Embedding data
    embedding_type TEXT NOT NULL,       -- 'base' or 'neighborhood'
    embedding vector(1536) NOT NULL,    -- OpenAI text-embedding-3-small

    -- Text that was embedded (for debugging/recomputation)
    embedded_text TEXT,

    -- Metadata
    model_name TEXT DEFAULT 'text-embedding-3-small',
    content_hash TEXT,                  -- MD5 of embedded_text for staleness detection

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Ensure unique embedding per node + type
    UNIQUE (node_label, source_id, embedding_type)
);

COMMENT ON TABLE graphrag.node_embeddings IS
'Vector embeddings for graph nodes. Supports base (content only) and neighborhood (content + graph context) embeddings.';

COMMENT ON COLUMN graphrag.node_embeddings.embedding_type IS
'base: Pure node content embedding. neighborhood: Content + 1-hop neighbor context embedding.';

-- =============================================================================
-- Subgraph Cache Table
-- =============================================================================
-- Caches extracted subgraphs in text format for LLM context generation.
-- This avoids re-computing expensive graph traversals.

CREATE TABLE graphrag.subgraph_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Cache key: starting node + parameters
    node_label TEXT NOT NULL,
    source_id TEXT NOT NULL,
    max_hops INT NOT NULL DEFAULT 2,
    max_nodes INT NOT NULL DEFAULT 20,

    -- Cached content
    subgraph_text TEXT NOT NULL,        -- Human-readable subgraph for LLM
    subgraph_json JSONB,                -- Structured subgraph data
    node_count INT,                     -- Number of nodes in subgraph
    edge_count INT,                     -- Number of edges in subgraph

    -- Cache validity
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,             -- NULL = no expiration
    is_valid BOOLEAN DEFAULT TRUE,      -- Set to FALSE when source data changes

    -- Ensure unique cache entry per node + parameters
    UNIQUE (node_label, source_id, max_hops, max_nodes)
);

COMMENT ON TABLE graphrag.subgraph_cache IS
'Cached subgraph extractions for LLM context. Invalidate when source nodes or edges change.';

-- =============================================================================
-- Graph Statistics Table
-- =============================================================================
-- Tracks graph statistics for monitoring and optimization.

CREATE TABLE graphrag.graph_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- What was measured
    stat_type TEXT NOT NULL,            -- 'node_count', 'edge_count', 'embedding_coverage', etc.
    stat_key TEXT,                      -- Subcategory (e.g., node label, edge label)

    -- Values
    stat_value NUMERIC,
    stat_json JSONB,                    -- For complex stats

    -- Timestamps
    computed_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE graphrag.graph_stats IS
'Statistics about the graph for monitoring and optimization.';

-- =============================================================================
-- Node ID Mapping Table
-- =============================================================================
-- Maps between AGE internal IDs and our source IDs for efficient lookups.

CREATE TABLE graphrag.node_id_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    node_label TEXT NOT NULL,
    source_id TEXT NOT NULL,
    age_id BIGINT NOT NULL,             -- AGE's internal vertex ID

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (node_label, source_id),
    UNIQUE (age_id)
);

COMMENT ON TABLE graphrag.node_id_map IS
'Maps between source IDs (from relational tables) and AGE internal vertex IDs.';

-- =============================================================================
-- Search History Table (Optional - for analytics)
-- =============================================================================
-- Tracks search queries for analytics and cache warming.

CREATE TABLE graphrag.search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Query info
    query_text TEXT,
    query_embedding vector(1536),
    search_type TEXT,                   -- 'vector', 'graph_enhanced', 'hybrid'

    -- Parameters
    params JSONB,

    -- Results summary
    result_count INT,
    top_result_id TEXT,
    top_result_score REAL,

    -- Timing
    execution_time_ms INT,
    searched_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE graphrag.search_history IS
'Search query history for analytics and cache warming.';
