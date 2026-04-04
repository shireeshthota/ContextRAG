-- =============================================================================
-- GraphRAG Migration 006: Create Graph + Vector Search Functions
-- =============================================================================
-- This migration creates all the core functions for GraphRAG operations:
--
-- Graph Traversal:
-- - get_node_neighborhood(): Get 1-hop neighbors
-- - get_extended_context(): Get multi-hop context
-- - build_graph_context_text(): Build text from graph structure
--
-- Structural Analysis:
-- - find_structurally_similar(): Find nodes sharing neighbors
--
-- Vector Search:
-- - vector_search(): Basic vector similarity search
-- - graph_enhanced_search(): Vector + graph expansion
-- - hybrid_search(): Vector + filters
--
-- LLM Context:
-- - extract_subgraph_for_llm(): Extract subgraph as LLM-ready text
-- - path_similarity_search(): Path-based ranking with explanations
-- =============================================================================

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, graphrag, "$user", public;

-- =============================================================================
-- GRAPH TRAVERSAL FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- get_node_neighborhood: Get immediate (1-hop) neighbors of a node
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.get_node_neighborhood(
    p_node_label TEXT,
    p_source_id TEXT,
    p_edge_types TEXT[] DEFAULT NULL  -- NULL = all edge types
)
RETURNS TABLE (
    neighbor_label TEXT,
    neighbor_source_id TEXT,
    neighbor_properties JSONB,
    edge_type TEXT,
    edge_direction TEXT,  -- 'outgoing' or 'incoming'
    edge_properties JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cypher_query TEXT;
    v_edge_filter TEXT := '';
BEGIN
    -- Build edge type filter if specified
    IF p_edge_types IS NOT NULL AND array_length(p_edge_types, 1) > 0 THEN
        v_edge_filter := ' WHERE type(r) IN [' ||
            (SELECT string_agg('''' || unnest || '''', ', ') FROM unnest(p_edge_types)) || ']';
    END IF;

    -- Query for outgoing edges
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})-[r]->(m)
        %s
        RETURN labels(m)[0] as neighbor_label,
               m.source_id as neighbor_source_id,
               properties(m) as neighbor_properties,
               type(r) as edge_type,
               'outgoing' as edge_direction,
               properties(r) as edge_properties
    $cypher$, p_node_label, p_source_id, v_edge_filter))
    AS (neighbor_label agtype, neighbor_source_id agtype, neighbor_properties agtype,
        edge_type agtype, edge_direction agtype, edge_properties agtype);

    -- Query for incoming edges
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})<-[r]-(m)
        %s
        RETURN labels(m)[0] as neighbor_label,
               m.source_id as neighbor_source_id,
               properties(m) as neighbor_properties,
               type(r) as edge_type,
               'incoming' as edge_direction,
               properties(r) as edge_properties
    $cypher$, p_node_label, p_source_id, v_edge_filter))
    AS (neighbor_label agtype, neighbor_source_id agtype, neighbor_properties agtype,
        edge_type agtype, edge_direction agtype, edge_properties agtype);
END;
$$;

COMMENT ON FUNCTION graphrag.get_node_neighborhood IS
'Get all 1-hop neighbors of a node with edge information. Optionally filter by edge types.';

-- -----------------------------------------------------------------------------
-- get_extended_context: Get multi-hop context around a node
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.get_extended_context(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 2,
    p_max_nodes INT DEFAULT 50
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    properties JSONB,
    path_length INT,
    path_description TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- For simplicity, we execute multiple queries for each hop level
    -- AGE supports variable-length paths but the syntax varies by version

    -- Return the starting node
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})
        RETURN labels(n)[0] as node_label,
               n.source_id as source_id,
               properties(n) as properties,
               0 as path_length,
               'origin' as path_description
    $cypher$, p_node_label, p_source_id))
    AS (node_label agtype, source_id agtype, properties agtype,
        path_length agtype, path_description agtype);

    -- 1-hop neighbors
    IF p_max_hops >= 1 THEN
        RETURN QUERY
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I {source_id: %L})-[r]-(m)
            RETURN DISTINCT labels(m)[0] as node_label,
                   m.source_id as source_id,
                   properties(m) as properties,
                   1 as path_length,
                   labels(n)[0] || ' -[' || type(r) || ']- ' || labels(m)[0] as path_description
            LIMIT %s
        $cypher$, p_node_label, p_source_id, p_max_nodes))
        AS (node_label agtype, source_id agtype, properties agtype,
            path_length agtype, path_description agtype);
    END IF;

    -- 2-hop neighbors
    IF p_max_hops >= 2 THEN
        RETURN QUERY
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I {source_id: %L})-[r1]-(m1)-[r2]-(m2)
            WHERE n <> m2 AND m1 <> m2
            RETURN DISTINCT labels(m2)[0] as node_label,
                   m2.source_id as source_id,
                   properties(m2) as properties,
                   2 as path_length,
                   labels(n)[0] || ' -[' || type(r1) || ']- ' || labels(m1)[0] || ' -[' || type(r2) || ']- ' || labels(m2)[0] as path_description
            LIMIT %s
        $cypher$, p_node_label, p_source_id, p_max_nodes))
        AS (node_label agtype, source_id agtype, properties agtype,
            path_length agtype, path_description agtype);
    END IF;

    -- 3-hop neighbors (expensive, use sparingly)
    IF p_max_hops >= 3 THEN
        RETURN QUERY
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I {source_id: %L})-[r1]-(m1)-[r2]-(m2)-[r3]-(m3)
            WHERE n <> m3 AND m1 <> m3 AND m2 <> m3
            RETURN DISTINCT labels(m3)[0] as node_label,
                   m3.source_id as source_id,
                   properties(m3) as properties,
                   3 as path_length,
                   labels(n)[0] || ' -> ... -> ' || labels(m3)[0] as path_description
            LIMIT %s
        $cypher$, p_node_label, p_source_id, p_max_nodes / 2))
        AS (node_label agtype, source_id agtype, properties agtype,
            path_length agtype, path_description agtype);
    END IF;
END;
$$;

COMMENT ON FUNCTION graphrag.get_extended_context IS
'Get multi-hop context around a node. Returns all reachable nodes within max_hops with path information.';

-- -----------------------------------------------------------------------------
-- build_graph_context_text: Build human-readable text from graph structure
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.build_graph_context_text(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 1
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_result TEXT := '';
    v_node_text TEXT;
    v_neighbor_text TEXT;
    rec RECORD;
BEGIN
    -- Get the node's own properties
    SELECT * INTO rec FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})
        RETURN properties(n) as props
    $cypher$, p_node_label, p_source_id))
    AS (props agtype);

    IF rec IS NOT NULL THEN
        v_result := p_node_label || ': ' || rec.props::TEXT || E'\n\n';
    END IF;

    -- Add relationship context
    v_result := v_result || 'Relationships:' || E'\n';

    FOR rec IN
        SELECT * FROM graphrag.get_node_neighborhood(p_node_label, p_source_id)
    LOOP
        IF rec.edge_direction = 'outgoing' THEN
            v_result := v_result || '  -[' || rec.edge_type || ']-> ' ||
                       rec.neighbor_label || ' (' || rec.neighbor_source_id || ')' || E'\n';
        ELSE
            v_result := v_result || '  <-[' || rec.edge_type || ']- ' ||
                       rec.neighbor_label || ' (' || rec.neighbor_source_id || ')' || E'\n';
        END IF;
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION graphrag.build_graph_context_text IS
'Build human-readable text describing a node and its relationships for embedding or LLM context.';

-- =============================================================================
-- STRUCTURAL SIMILARITY FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- find_structurally_similar: Find nodes that share neighbors
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.find_structurally_similar(
    p_node_label TEXT,
    p_source_id TEXT,
    p_search_label TEXT DEFAULT NULL,  -- NULL = same as p_node_label
    p_min_shared INT DEFAULT 1,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    similar_source_id TEXT,
    shared_neighbors INT,
    shared_neighbor_details JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_search_label TEXT;
BEGIN
    v_search_label := COALESCE(p_search_label, p_node_label);

    -- Find nodes that share neighbors with the input node
    RETURN QUERY
    SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
        MATCH (n:%I {source_id: %L})-[]-(shared)-[]-(similar:%I)
        WHERE n <> similar
        WITH similar, collect(DISTINCT shared) as shared_nodes
        WHERE size(shared_nodes) >= %s
        RETURN similar.source_id as similar_source_id,
               size(shared_nodes) as shared_neighbors,
               [s IN shared_nodes | {label: labels(s)[0], id: s.source_id}] as shared_neighbor_details
        ORDER BY shared_neighbors DESC
        LIMIT %s
    $cypher$, p_node_label, p_source_id, v_search_label, p_min_shared, p_limit))
    AS (similar_source_id agtype, shared_neighbors agtype, shared_neighbor_details agtype);
END;
$$;

COMMENT ON FUNCTION graphrag.find_structurally_similar IS
'Find nodes that share neighbors with the input node (structural similarity).';

-- =============================================================================
-- VECTOR SEARCH FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- vector_search: Basic vector similarity search
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.vector_search(
    p_query_embedding vector(1536),
    p_node_label TEXT DEFAULT NULL,     -- NULL = search all node types
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_min_similarity REAL DEFAULT 0.0
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    similarity REAL,
    embedded_text TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_node_label IS NULL THEN
        -- Search across all node types
        RETURN QUERY
        SELECT
            e.node_label,
            e.source_id,
            (1 - (e.embedding <=> p_query_embedding))::REAL as similarity,
            e.embedded_text
        FROM graphrag.node_embeddings e
        WHERE e.embedding_type = p_embedding_type
          AND (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
        ORDER BY e.embedding <=> p_query_embedding
        LIMIT p_limit;
    ELSE
        -- Search specific node type
        RETURN QUERY
        SELECT
            e.node_label,
            e.source_id,
            (1 - (e.embedding <=> p_query_embedding))::REAL as similarity,
            e.embedded_text
        FROM graphrag.node_embeddings e
        WHERE e.embedding_type = p_embedding_type
          AND e.node_label = p_node_label
          AND (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
        ORDER BY e.embedding <=> p_query_embedding
        LIMIT p_limit;
    END IF;
END;
$$;

COMMENT ON FUNCTION graphrag.vector_search IS
'Basic vector similarity search across node embeddings. Optionally filter by node type.';

-- -----------------------------------------------------------------------------
-- graph_enhanced_search: Vector search with graph expansion
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.graph_enhanced_search(
    p_query_embedding vector(1536),
    p_node_label TEXT DEFAULT NULL,
    p_limit INT DEFAULT 10,
    p_expansion_hops INT DEFAULT 1,
    p_embedding_type TEXT DEFAULT 'base'
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    similarity REAL,
    expansion_context JSONB,
    combined_score REAL
)
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_context JSONB;
    v_neighbor_count INT;
BEGIN
    -- First, do vector search to find candidates
    FOR rec IN
        SELECT * FROM graphrag.vector_search(
            p_query_embedding,
            p_node_label,
            p_embedding_type,
            p_limit * 2,  -- Get more candidates for re-ranking
            0.0
        )
    LOOP
        -- Get graph context for each candidate
        SELECT jsonb_agg(jsonb_build_object(
            'label', neighbor_label,
            'id', neighbor_source_id,
            'edge', edge_type,
            'direction', edge_direction
        )), COUNT(*)
        INTO v_context, v_neighbor_count
        FROM graphrag.get_node_neighborhood(rec.node_label, rec.source_id);

        -- Compute combined score (vector similarity + graph connectivity bonus)
        -- More connected nodes get a slight boost
        node_label := rec.node_label;
        source_id := rec.source_id;
        similarity := rec.similarity;
        expansion_context := COALESCE(v_context, '[]'::jsonb);
        combined_score := rec.similarity + (LEAST(v_neighbor_count, 10) * 0.01)::REAL;

        RETURN NEXT;
    END LOOP;

    -- Re-sort by combined score and limit
    RETURN QUERY
    SELECT gs.node_label, gs.source_id, gs.similarity, gs.expansion_context, gs.combined_score
    FROM graphrag.graph_enhanced_search(
        p_query_embedding, p_node_label, p_limit * 2, p_expansion_hops, p_embedding_type
    ) gs
    ORDER BY gs.combined_score DESC
    LIMIT p_limit;
END;
$$;

-- Simplified version that actually works
DROP FUNCTION IF EXISTS graphrag.graph_enhanced_search;

CREATE OR REPLACE FUNCTION graphrag.graph_enhanced_search(
    p_query_embedding vector(1536),
    p_node_label TEXT DEFAULT NULL,
    p_limit INT DEFAULT 10,
    p_expansion_hops INT DEFAULT 1,
    p_embedding_type TEXT DEFAULT 'base'
)
RETURNS TABLE (
    node_label TEXT,
    source_id TEXT,
    similarity REAL,
    neighbor_count INT,
    combined_score REAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH vector_results AS (
        SELECT
            v.node_label,
            v.source_id,
            v.similarity
        FROM graphrag.vector_search(
            p_query_embedding,
            p_node_label,
            p_embedding_type,
            p_limit * 3,  -- Get extra candidates
            0.0
        ) v
    ),
    with_neighbors AS (
        SELECT
            vr.node_label,
            vr.source_id,
            vr.similarity,
            (SELECT COUNT(*)::INT FROM graphrag.get_node_neighborhood(vr.node_label, vr.source_id)) as neighbor_count
        FROM vector_results vr
    )
    SELECT
        wn.node_label,
        wn.source_id,
        wn.similarity,
        wn.neighbor_count,
        (wn.similarity + (LEAST(wn.neighbor_count, 10) * 0.01))::REAL as combined_score
    FROM with_neighbors wn
    ORDER BY combined_score DESC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION graphrag.graph_enhanced_search IS
'Vector search with graph expansion. Boosts results that have more graph connections.';

-- -----------------------------------------------------------------------------
-- hybrid_search: Vector search with SQL filters
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.hybrid_search(
    p_query_embedding vector(1536),
    p_node_label TEXT,
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 10,
    p_property_filter JSONB DEFAULT NULL,  -- e.g., {"status": "open", "priority": "high"}
    p_min_similarity REAL DEFAULT 0.0
)
RETURNS TABLE (
    source_id TEXT,
    similarity REAL,
    properties JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cypher_where TEXT := '';
    v_filter_key TEXT;
    v_filter_value TEXT;
BEGIN
    -- Build Cypher WHERE clause from property filter
    IF p_property_filter IS NOT NULL THEN
        FOR v_filter_key, v_filter_value IN
            SELECT * FROM jsonb_each_text(p_property_filter)
        LOOP
            IF v_cypher_where = '' THEN
                v_cypher_where := format('WHERE n.%I = %L', v_filter_key, v_filter_value);
            ELSE
                v_cypher_where := v_cypher_where || format(' AND n.%I = %L', v_filter_key, v_filter_value);
            END IF;
        END LOOP;
    END IF;

    -- Get filtered source_ids from graph, then join with embeddings
    RETURN QUERY
    WITH filtered_nodes AS (
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (n:%I)
            %s
            RETURN n.source_id as source_id, properties(n) as properties
        $cypher$, p_node_label, v_cypher_where))
        AS (source_id agtype, properties agtype)
    ),
    with_similarity AS (
        SELECT
            fn.source_id::TEXT,
            (1 - (e.embedding <=> p_query_embedding))::REAL as similarity,
            fn.properties::JSONB
        FROM filtered_nodes fn
        JOIN graphrag.node_embeddings e
            ON e.node_label = p_node_label
            AND e.source_id = fn.source_id::TEXT
            AND e.embedding_type = p_embedding_type
        WHERE (1 - (e.embedding <=> p_query_embedding)) >= p_min_similarity
    )
    SELECT ws.source_id, ws.similarity, ws.properties
    FROM with_similarity ws
    ORDER BY ws.similarity DESC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION graphrag.hybrid_search IS
'Vector search with property filtering using Cypher. Filter by graph node properties.';

-- =============================================================================
-- LLM CONTEXT FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- extract_subgraph_for_llm: Extract subgraph as LLM-ready text
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.extract_subgraph_for_llm(
    p_node_label TEXT,
    p_source_id TEXT,
    p_max_hops INT DEFAULT 2,
    p_max_nodes INT DEFAULT 20,
    p_use_cache BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_result TEXT := '';
    v_cached_text TEXT;
    rec RECORD;
    v_node_count INT := 0;
    v_current_label TEXT;
BEGIN
    -- Check cache first
    IF p_use_cache THEN
        SELECT subgraph_text INTO v_cached_text
        FROM graphrag.subgraph_cache
        WHERE node_label = p_node_label
          AND source_id = p_source_id
          AND max_hops = p_max_hops
          AND max_nodes = p_max_nodes
          AND is_valid = TRUE
          AND (expires_at IS NULL OR expires_at > NOW());

        IF v_cached_text IS NOT NULL THEN
            RETURN v_cached_text;
        END IF;
    END IF;

    -- Build subgraph text
    v_result := '=== SUBGRAPH CONTEXT ===' || E'\n\n';

    -- Group by path length for readability
    v_current_label := '';

    FOR rec IN
        SELECT * FROM graphrag.get_extended_context(p_node_label, p_source_id, p_max_hops, p_max_nodes)
        ORDER BY path_length, node_label
    LOOP
        -- Add section headers
        IF rec.path_length::INT = 0 THEN
            v_result := v_result || '## Primary Entity' || E'\n';
        ELSIF v_current_label = '' OR v_current_label <> rec.path_length::TEXT THEN
            v_result := v_result || E'\n' || '## ' || rec.path_length::TEXT || '-hop Neighbors' || E'\n';
            v_current_label := rec.path_length::TEXT;
        END IF;

        -- Add node info
        v_result := v_result || '- ' || rec.node_label || ' (' || rec.source_id || '): ';
        v_result := v_result || rec.properties::TEXT || E'\n';

        -- Add path if not origin
        IF rec.path_length::INT > 0 THEN
            v_result := v_result || '  Path: ' || rec.path_description || E'\n';
        END IF;

        v_node_count := v_node_count + 1;

        IF v_node_count >= p_max_nodes THEN
            v_result := v_result || E'\n' || '... (truncated at ' || p_max_nodes || ' nodes)';
            EXIT;
        END IF;
    END LOOP;

    -- Cache the result
    IF p_use_cache THEN
        INSERT INTO graphrag.subgraph_cache (
            node_label, source_id, max_hops, max_nodes,
            subgraph_text, node_count, computed_at
        )
        VALUES (
            p_node_label, p_source_id, p_max_hops, p_max_nodes,
            v_result, v_node_count, NOW()
        )
        ON CONFLICT (node_label, source_id, max_hops, max_nodes)
        DO UPDATE SET
            subgraph_text = EXCLUDED.subgraph_text,
            node_count = EXCLUDED.node_count,
            computed_at = NOW(),
            is_valid = TRUE;
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION graphrag.extract_subgraph_for_llm IS
'Extract a subgraph around a node as human-readable text for LLM context. Uses caching for performance.';

-- -----------------------------------------------------------------------------
-- path_similarity_search: Search with path-based explanations
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.path_similarity_search(
    p_query_embedding vector(1536),
    p_target_label TEXT,           -- What we're searching for (e.g., 'KBArticle')
    p_context_label TEXT,          -- Context node to expand from (e.g., 'Ticket')
    p_context_source_id TEXT,
    p_limit INT DEFAULT 5,
    p_embedding_type TEXT DEFAULT 'base'
)
RETURNS TABLE (
    target_source_id TEXT,
    similarity REAL,
    path_to_context TEXT,
    relevance_explanation TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Find target nodes that are both:
    -- 1. Semantically similar to query
    -- 2. Connected to the context node via graph paths

    RETURN QUERY
    WITH semantic_matches AS (
        -- Vector search on target type
        SELECT
            v.source_id,
            v.similarity
        FROM graphrag.vector_search(
            p_query_embedding,
            p_target_label,
            p_embedding_type,
            p_limit * 5,
            0.3  -- Minimum similarity threshold
        ) v
    ),
    path_connections AS (
        -- Find paths from context to semantic matches
        SELECT * FROM ag_catalog.cypher('support_graph', format($cypher$
            MATCH (ctx:%I {source_id: %L})-[*1..3]-(target:%I)
            WITH target, min(length(shortestPath((ctx)-[*]-(target)))) as dist
            RETURN target.source_id as target_id, dist
        $cypher$, p_context_label, p_context_source_id, p_target_label))
        AS (target_id agtype, dist agtype)
    )
    SELECT
        sm.source_id as target_source_id,
        sm.similarity,
        CASE
            WHEN pc.dist IS NOT NULL THEN p_context_label || ' -> ' || pc.dist::TEXT || ' hops -> ' || p_target_label
            ELSE 'No direct path'
        END as path_to_context,
        CASE
            WHEN pc.dist IS NOT NULL AND pc.dist::INT = 1 THEN 'Directly connected - highly relevant'
            WHEN pc.dist IS NOT NULL AND pc.dist::INT = 2 THEN 'Connected via shared entity'
            WHEN pc.dist IS NOT NULL THEN 'Indirectly connected (' || pc.dist::TEXT || ' hops)'
            ELSE 'Found via semantic similarity only'
        END as relevance_explanation
    FROM semantic_matches sm
    LEFT JOIN path_connections pc ON pc.target_id::TEXT = sm.source_id
    ORDER BY
        CASE WHEN pc.dist IS NOT NULL THEN 0 ELSE 1 END,  -- Connected first
        pc.dist::INT NULLS LAST,                          -- Shorter paths first
        sm.similarity DESC                                 -- Then by similarity
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION graphrag.path_similarity_search IS
'Search for targets that are both semantically similar and graph-connected to a context node. Provides path explanations.';

-- =============================================================================
-- EMBEDDING MANAGEMENT FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- store_node_embedding: Store an embedding for a graph node
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.store_node_embedding(
    p_node_label TEXT,
    p_source_id TEXT,
    p_embedding_type TEXT,
    p_embedding vector(1536),
    p_embedded_text TEXT DEFAULT NULL,
    p_model_name TEXT DEFAULT 'text-embedding-3-small'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
    v_content_hash TEXT;
BEGIN
    -- Compute content hash if text provided
    IF p_embedded_text IS NOT NULL THEN
        v_content_hash := md5(p_embedded_text);
    END IF;

    INSERT INTO graphrag.node_embeddings (
        node_label, source_id, embedding_type, embedding,
        embedded_text, model_name, content_hash
    )
    VALUES (
        p_node_label, p_source_id, p_embedding_type, p_embedding,
        p_embedded_text, p_model_name, v_content_hash
    )
    ON CONFLICT (node_label, source_id, embedding_type)
    DO UPDATE SET
        embedding = EXCLUDED.embedding,
        embedded_text = EXCLUDED.embedded_text,
        model_name = EXCLUDED.model_name,
        content_hash = EXCLUDED.content_hash,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION graphrag.store_node_embedding IS
'Store or update an embedding for a graph node. Handles upsert on conflict.';

-- -----------------------------------------------------------------------------
-- get_unembedded_nodes: Find nodes that need embeddings
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.get_unembedded_nodes(
    p_node_label TEXT,
    p_embedding_type TEXT DEFAULT 'base',
    p_limit INT DEFAULT 100
)
RETURNS TABLE (
    source_id TEXT,
    node_text TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_text_property TEXT;
BEGIN
    -- Determine which property to use for text based on node type
    v_text_property := CASE p_node_label
        WHEN 'Ticket' THEN 'subject || ''. '' || description'
        WHEN 'Customer' THEN 'name || '' ('' || email || '')'
        WHEN 'Product' THEN 'name || '': '' || description'
        WHEN 'Agent' THEN 'name || '' - '' || team'
        WHEN 'KBArticle' THEN 'title || ''. '' || content'
        WHEN 'TicketMessage' THEN 'message'
        ELSE 'source_id'
    END;

    -- Find nodes without embeddings
    RETURN QUERY EXECUTE format($query$
        WITH existing AS (
            SELECT e.source_id
            FROM graphrag.node_embeddings e
            WHERE e.node_label = %L AND e.embedding_type = %L
        ),
        all_nodes AS (
            SELECT * FROM ag_catalog.cypher('support_graph', $cypher$
                MATCH (n:%I)
                RETURN n.source_id as source_id, %s as node_text
            $cypher$)
            AS (source_id agtype, node_text agtype)
        )
        SELECT an.source_id::TEXT, an.node_text::TEXT
        FROM all_nodes an
        WHERE an.source_id::TEXT NOT IN (SELECT e.source_id FROM existing e)
        LIMIT %s
    $query$, p_node_label, p_embedding_type, p_node_label, v_text_property, p_limit);
END;
$$;

COMMENT ON FUNCTION graphrag.get_unembedded_nodes IS
'Find nodes that do not have embeddings of the specified type.';

-- =============================================================================
-- CACHE MANAGEMENT FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- invalidate_subgraph_cache: Invalidate cache when data changes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.invalidate_subgraph_cache(
    p_node_label TEXT DEFAULT NULL,
    p_source_id TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    IF p_node_label IS NOT NULL AND p_source_id IS NOT NULL THEN
        -- Invalidate specific node
        UPDATE graphrag.subgraph_cache
        SET is_valid = FALSE
        WHERE node_label = p_node_label AND source_id = p_source_id;
    ELSIF p_node_label IS NOT NULL THEN
        -- Invalidate all nodes of a type
        UPDATE graphrag.subgraph_cache
        SET is_valid = FALSE
        WHERE node_label = p_node_label;
    ELSE
        -- Invalidate all
        UPDATE graphrag.subgraph_cache
        SET is_valid = FALSE;
    END IF;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION graphrag.invalidate_subgraph_cache IS
'Invalidate cached subgraphs. Call when graph data changes.';

-- -----------------------------------------------------------------------------
-- cleanup_expired_cache: Remove expired cache entries
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.cleanup_expired_cache()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    DELETE FROM graphrag.subgraph_cache
    WHERE (expires_at IS NOT NULL AND expires_at < NOW())
       OR is_valid = FALSE;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION graphrag.cleanup_expired_cache IS
'Remove expired and invalidated cache entries.';

-- =============================================================================
-- STATISTICS FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- get_graph_stats: Get statistics about the graph
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION graphrag.get_graph_stats()
RETURNS TABLE (
    stat_name TEXT,
    stat_value BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Node counts by type
    RETURN QUERY
    SELECT 'nodes_total'::TEXT, COUNT(*)::BIGINT
    FROM ag_catalog.cypher('support_graph', $$
        MATCH (n) RETURN n
    $$) AS (n agtype);

    RETURN QUERY
    SELECT 'edges_total'::TEXT, COUNT(*)::BIGINT
    FROM ag_catalog.cypher('support_graph', $$
        MATCH ()-[r]->() RETURN r
    $$) AS (r agtype);

    -- Embedding counts
    RETURN QUERY
    SELECT 'embeddings_base'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.node_embeddings
    WHERE embedding_type = 'base';

    RETURN QUERY
    SELECT 'embeddings_neighborhood'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.node_embeddings
    WHERE embedding_type = 'neighborhood';

    -- Cache stats
    RETURN QUERY
    SELECT 'cache_entries_valid'::TEXT, COUNT(*)::BIGINT
    FROM graphrag.subgraph_cache
    WHERE is_valid = TRUE;
END;
$$;

COMMENT ON FUNCTION graphrag.get_graph_stats IS
'Get statistics about the graph, embeddings, and caches.';
