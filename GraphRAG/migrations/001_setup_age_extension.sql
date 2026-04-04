-- =============================================================================
-- GraphRAG Migration 001: Apache AGE Extension Setup
-- =============================================================================
-- This migration installs the Apache AGE extension and creates the support graph.
-- Apache AGE adds graph database capabilities to PostgreSQL using Cypher queries.
--
-- Prerequisites:
-- - PostgreSQL 14+ with Apache AGE extension installed
-- - Superuser or extension creation privileges
--
-- To install AGE on your system:
-- - macOS: brew install apache-age
-- - Linux: See https://age.apache.org/docs/installation/
-- - Docker: Use apache/age image
-- =============================================================================

-- Install Apache AGE extension
CREATE EXTENSION IF NOT EXISTS age;

-- Load AGE into the current session
LOAD 'age';

-- Add ag_catalog to search path for convenience
SET search_path = ag_catalog, "$user", public;

-- =============================================================================
-- Create the Support Graph
-- =============================================================================
-- This graph will contain all CRM entities and their relationships.
-- The graph name 'support_graph' matches our support schema convention.

SELECT create_graph('support_graph');

-- =============================================================================
-- Create GraphRAG Schema
-- =============================================================================
-- This schema holds vector embeddings, caches, and utility functions
-- that work alongside the graph data.

CREATE SCHEMA IF NOT EXISTS graphrag;

COMMENT ON SCHEMA graphrag IS 'GraphRAG: Graph-enhanced Retrieval Augmented Generation using Apache AGE';

-- =============================================================================
-- Helper function to ensure AGE is loaded for each session
-- =============================================================================
CREATE OR REPLACE FUNCTION graphrag.ensure_age_loaded()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Load AGE extension
    LOAD 'age';
    -- Set search path to include ag_catalog
    SET search_path = ag_catalog, graphrag, support, "$user", public;
END;
$$;

COMMENT ON FUNCTION graphrag.ensure_age_loaded() IS
'Ensures Apache AGE is loaded and search path is set correctly. Call at session start.';

-- =============================================================================
-- Verification Queries
-- =============================================================================
-- Run these to verify the installation:
--
-- Check AGE extension is installed:
-- SELECT * FROM pg_extension WHERE extname = 'age';
--
-- Check graph was created:
-- SELECT * FROM ag_catalog.ag_graph WHERE name = 'support_graph';
--
-- Check graphrag schema exists:
-- SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'graphrag';
-- =============================================================================
