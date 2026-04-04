# GraphRAG PostgreSQL Extension

This directory contains the PostgreSQL extension files for GraphRAG.

## Files

- `graphrag.control` - Extension metadata
- `graphrag--1.0.sql` - Complete extension SQL (schema, tables, indexes, functions)
- `Makefile` - PGXS build configuration

## Prerequisites

- PostgreSQL 14+
- Apache AGE extension
- pgvector extension

## Installation

### Option 1: Manual Installation

```bash
# Find PostgreSQL extension directory
SHAREDIR=$(pg_config --sharedir)

# Copy extension files
sudo cp graphrag.control "$SHAREDIR/extension/"
sudo cp graphrag--1.0.sql "$SHAREDIR/extension/"
```

### Option 2: Using Makefile

```bash
make install
```

## Usage

```sql
-- Create the extension
CREATE EXTENSION graphrag;

-- Ensure AGE is loaded (call at session start)
SELECT graphrag.ensure_age_loaded();

-- Create your graph
SELECT create_graph('my_graph');
```

## Dependencies

The extension requires these extensions to be installed:
- `age` (Apache AGE)
- `vector` (pgvector)

Both are automatically created if not present when you `CREATE EXTENSION graphrag`.

## Included Components

### Schema
- `graphrag` schema for all objects

### Tables
- `node_embeddings` - Vector embeddings for graph nodes
- `subgraph_cache` - Cached subgraph extractions
- `node_id_map` - AGE ID to source ID mapping
- `graph_stats` - Statistics tracking
- `search_history` - Query analytics (optional)

### Indexes
- HNSW indexes for vector search (separate for base/neighborhood)
- B-tree indexes for lookups

### Functions
- Graph traversal: `get_node_neighborhood`, `get_extended_context`, `build_graph_context_text`
- Vector search: `vector_search`, `graph_enhanced_search`, `hybrid_search`
- LLM context: `extract_subgraph_for_llm`, `path_similarity_search`
- Utilities: `store_node_embedding`, `invalidate_subgraph_cache`, `get_graph_stats`
