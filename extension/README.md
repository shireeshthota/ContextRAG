# ContextRAG PostgreSQL Extension

A PostgreSQL extension for Contextual Row-based RAG (Retrieval-Augmented Generation) that enriches database rows with optional contextual layers for more accurate, explainable retrieval.

## Requirements

- PostgreSQL 14+
- pgvector extension

## Installation

```bash
# Using PGXS
make
sudo make install

# In PostgreSQL
CREATE EXTENSION contextrag;
```

## Core Concepts

### Entities
Entities are the canonical registry of objects you want to search. Each entity:
- Links to a source table row (schema, table, id)
- Has a type (e.g., 'ticket', 'kb_article', 'customer')
- Contains base content (JSONB) that represents the searchable text
- Includes a content hash for change detection

### Context
Context entries are key-value attributes that enrich entities:
- Each context has a type, key, value, and optional weight
- Context can expire (temporal relevance)
- Multiple contexts per entity are supported

### Embeddings
Multiple embedding types per entity:
- `base`: Embedding of the raw entity content
- `local_context`: Embedding of content + context together

## Core Functions

### Entity Management

```sql
-- Register an entity from source data
SELECT contextrag.register_entity(
    'support',           -- source schema
    'tickets',           -- source table
    '123',               -- source id
    'ticket',            -- entity type
    '{"subject": "Password reset not working", "body": "..."}'::JSONB
);

-- Add context to an entity
SELECT contextrag.add_context(
    entity_id,
    'category',          -- context type
    'topic',             -- context key
    'authentication',    -- context value
    1.0                  -- weight
);
```

### Search Functions

```sql
-- Basic vector search
SELECT * FROM contextrag.vector_search(
    query_embedding,     -- vector(3072)
    'base',              -- embedding type
    10                   -- limit
);

-- Multi-embedding search (combines base + context scores)
SELECT * FROM contextrag.multi_embedding_search(
    query_embedding,
    0.7,                 -- base weight
    0.3,                 -- context weight
    10
);

-- Hybrid search with metadata filters
SELECT * FROM contextrag.hybrid_search(
    query_embedding,
    'base',
    10,
    'ticket',            -- entity type filter
    '{"priority": "high"}'::JSONB  -- metadata filter
);

-- Context-aware search
SELECT * FROM contextrag.context_aware_search(
    query_embedding,
    'base',
    10,
    'ticket',
    'category',          -- context type filter
    'status',            -- context key filter
    'open'               -- context value filter
);
```

### Maintenance Functions

```sql
-- Get entities needing re-embedding
SELECT * FROM contextrag.get_stale_entities('base', 100);

-- Get entities without embeddings
SELECT * FROM contextrag.get_unembedded_entities('base', NULL, 100);

-- Extension statistics
SELECT * FROM contextrag.get_stats();

-- Clean up expired context
SELECT contextrag.cleanup_expired_context();
```

## Schema

### Tables

- `contextrag.entities` - Canonical entity registry
- `contextrag.entity_context` - Context attributes per entity
- `contextrag.entity_embeddings` - Vector embeddings per entity

### Indexes

- HNSW indexes on embeddings (separate per embedding_type)
- B-tree indexes on source columns, entity_type, is_active
- GIN index on metadata JSONB

## Technical Details

- **Embedding dimensions**: vector(3072) for OpenAI text-embedding-3-large
- **HNSW parameters**: m=16, ef_construction=64
- **Content hashing**: MD5 for change detection
- **UUID primary keys**: Distributed generation
