# ContextRAG Execution Plan

## Phase 1: Base + Local Context Embeddings

### Status: Complete

| Step | Task | Status |
|------|------|--------|
| 1 | Create project structure | Done |
| 2 | PostgreSQL extension core (control, SQL, Makefile) | Done |
| 3 | Create indexes (HNSW, B-tree, GIN) | Done |
| 4 | Core functions (register, search, maintenance) | Done |
| 5 | Test project schema (support tickets) | Done |
| 6 | Seed data & entity registration | Done |
| 7 | Python embedding helpers | Done |
| 8 | Query examples & documentation | Done |

## Files Created

### Extension
- [x] `extension/contextrag.control` - Extension metadata
- [x] `extension/contextrag--1.0.sql` - Complete schema + functions
- [x] `extension/Makefile` - PGXS build file
- [x] `extension/README.md` - Extension documentation

### Migrations
- [x] `migrations/001_create_core_tables.sql` - Tables
- [x] `migrations/002_create_indexes.sql` - Indexes
- [x] `migrations/003_create_functions.sql` - Functions

### Test Project
- [x] `test_project/schema/support_tickets.sql` - Sample CRM schema
- [x] `test_project/data/seed_data.sql` - Sample data
- [x] `test_project/data/register_entities.sql` - Entity registration
- [x] `test_project/queries/search_examples.sql` - Query demos
- [x] `test_project/README.md` - Test project docs

### Python
- [x] `python/requirements.txt` - Dependencies
- [x] `python/embeddings.py` - OpenAI embedding generation
- [x] `python/batch_embed.py` - Batch embedding processor
- [x] `python/README.md` - Python helper docs

### Scripts & Docs
- [x] `scripts/install.sh` - Installation script
- [x] `scripts/setup_test_db.sh` - Test database setup
- [x] `README.md` - Main project documentation
- [x] `EXECUTION_PLAN.md` - This file

## Verification Checklist

### Installation
```bash
# Install extension or run migrations
./scripts/install.sh contextrag_test

# Or manually:
psql -d testdb -c "CREATE EXTENSION pgvector;"
psql -d testdb -f migrations/001_create_core_tables.sql
psql -d testdb -f migrations/002_create_indexes.sql
psql -d testdb -f migrations/003_create_functions.sql
```

### Schema Verification
```sql
SELECT * FROM contextrag.get_stats();
```

### Entity Registration Test
```sql
SELECT contextrag.register_entity(
    'support', 'tickets', '1', 'ticket',
    '{"subject": "Test ticket"}'::JSONB
);
```

### Context Addition
```sql
SELECT contextrag.add_context(
    entity_id, 'category', 'status', 'open'
);
```

### Python Embedding Test
```bash
cd python
pip install -r requirements.txt
export OPENAI_API_KEY=your_key
python batch_embed.py --dry-run
python batch_embed.py --embedding-type base
```

### Vector Search Test
```sql
SELECT * FROM contextrag.vector_search(
    query_embedding::vector(1536),
    'base', 10, 'ticket'
);
```

## Future Phases (Out of Scope)

### Phase 2: Graph Context
- `contextrag.entity_edges` table
- Graph traversal functions
- Neighborhood expansion for context

### Phase 3: Propagated Embeddings
- `propagated_context` embedding type
- Context decay rules
- Path materialization
- Transitive context propagation

### Phase 4: Auto-Registration via Schema Introspection
- `contextrag.auto_register(schema, table, entity_type, config)` function
- Auto-discover text columns (`subject`, `description`, `content`, `title`, `body`) via `information_schema.columns`
- Follow foreign keys via `pg_constraint` to join related tables and pull in context automatically
- Infer context attributes from low-cardinality columns (`status`, `priority`, `category`, `type`)
- Assign default weights by convention with optional JSONB overrides
- Goal: replace manual registration scripts with a single function call

## Technical Notes

### Embedding Configuration
- Model: `text-embedding-3-small`
- Dimensions: 1536
- HNSW params: m=16, ef_construction=64

### Index Strategy
- Separate HNSW index per embedding_type (partial indexes)
- Prevents mixing semantics between base and context embeddings
- Optimal for filtered queries

### Content Hashing
- MD5 hash of base_content for change detection
- Used by `get_stale_entities()` to find outdated embeddings
