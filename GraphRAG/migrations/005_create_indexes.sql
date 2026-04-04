-- =============================================================================
-- GraphRAG Migration 005: Create Indexes
-- =============================================================================
-- This migration creates indexes for efficient vector search and graph lookups.
--
-- Index Types:
-- - HNSW indexes for vector similarity search (pgvector)
-- - B-tree indexes for scalar lookups
-- - Partial indexes for embedding type filtering
-- =============================================================================

-- =============================================================================
-- HNSW Vector Indexes
-- =============================================================================
-- HNSW (Hierarchical Navigable Small World) indexes enable fast approximate
-- nearest neighbor search. We create separate indexes per embedding_type
-- to avoid mixing different semantic spaces.

-- Index for 'base' embeddings (pure node content)
CREATE INDEX idx_node_embeddings_base_hnsw
ON graphrag.node_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
WHERE embedding_type = 'base';

COMMENT ON INDEX graphrag.idx_node_embeddings_base_hnsw IS
'HNSW index for base embeddings. Uses cosine similarity for semantic search.';

-- Index for 'neighborhood' embeddings (content + graph context)
CREATE INDEX idx_node_embeddings_neighborhood_hnsw
ON graphrag.node_embeddings
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64)
WHERE embedding_type = 'neighborhood';

COMMENT ON INDEX graphrag.idx_node_embeddings_neighborhood_hnsw IS
'HNSW index for neighborhood embeddings. Includes graph context in similarity.';

-- =============================================================================
-- B-tree Indexes for Node Embeddings
-- =============================================================================

-- Fast lookup by node label and source ID
CREATE INDEX idx_node_embeddings_node_lookup
ON graphrag.node_embeddings (node_label, source_id);

-- Filter by embedding type
CREATE INDEX idx_node_embeddings_type
ON graphrag.node_embeddings (embedding_type);

-- Find stale embeddings (content_hash changed)
CREATE INDEX idx_node_embeddings_content_hash
ON graphrag.node_embeddings (content_hash);

-- =============================================================================
-- Subgraph Cache Indexes
-- =============================================================================

-- Fast cache lookup by node
CREATE INDEX idx_subgraph_cache_lookup
ON graphrag.subgraph_cache (node_label, source_id, max_hops, max_nodes)
WHERE is_valid = TRUE;

-- Find expired caches
CREATE INDEX idx_subgraph_cache_expires
ON graphrag.subgraph_cache (expires_at)
WHERE expires_at IS NOT NULL AND is_valid = TRUE;

-- =============================================================================
-- Node ID Map Indexes
-- =============================================================================

-- Lookup by AGE ID (for reverse mapping)
CREATE INDEX idx_node_id_map_age_id
ON graphrag.node_id_map (age_id);

-- =============================================================================
-- Search History Indexes
-- =============================================================================

-- Time-based queries for analytics
CREATE INDEX idx_search_history_time
ON graphrag.search_history (searched_at DESC);

-- By search type
CREATE INDEX idx_search_history_type
ON graphrag.search_history (search_type, searched_at DESC);

-- =============================================================================
-- Graph Statistics Indexes
-- =============================================================================

CREATE INDEX idx_graph_stats_lookup
ON graphrag.graph_stats (stat_type, stat_key, computed_at DESC);

-- =============================================================================
-- HNSW Index Parameter Explanation
-- =============================================================================
-- m = 16: Number of bi-directional links created for each node
--   - Higher values = better recall, more memory, slower build
--   - Default: 16, Range: 2-100
--
-- ef_construction = 64: Size of dynamic candidate list during index build
--   - Higher values = better recall, slower build
--   - Default: 64, Range: 4-1000
--
-- For queries, set ef_search (default: 40) for recall/speed tradeoff:
--   SET hnsw.ef_search = 100;  -- Higher recall, slower
--   SET hnsw.ef_search = 20;   -- Lower recall, faster
--
-- vector_cosine_ops: Use cosine similarity (most common for text embeddings)
-- Alternatives: vector_l2_ops (Euclidean), vector_ip_ops (inner product)
-- =============================================================================

-- =============================================================================
-- Index Statistics (Run after data load)
-- =============================================================================
-- After loading data, analyze tables for query planner:
--
-- ANALYZE graphrag.node_embeddings;
-- ANALYZE graphrag.subgraph_cache;
-- ANALYZE graphrag.node_id_map;
--
-- Check index sizes:
-- SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'graphrag';
-- =============================================================================
