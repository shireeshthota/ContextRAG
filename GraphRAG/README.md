# GraphRAG: Graph-Enhanced Retrieval Augmented Generation

A PostgreSQL-based Graph RAG system using Apache AGE for property graph storage and pgvector for semantic search. This implementation contrasts with the companion ContextRAG system to demonstrate when graph-based approaches excel.

## Overview

GraphRAG combines vector similarity search with graph structure to provide richer context for LLM-based applications. Unlike flat context attributes (ContextRAG), GraphRAG models explicit relationships between entities, enabling:

- **Multi-hop discovery**: Traverse relationships to find related entities
- **Structural similarity**: Find items that share graph neighbors
- **Path-based explanations**: Explain WHY results are relevant
- **Subgraph extraction**: Provide rich context including relationships

## Quick Start

```bash
# 1. Set up the test database
./scripts/setup_test_db.sh graphrag_test

# 2. Generate embeddings
cd python
pip install -r requirements.txt
export OPENAI_API_KEY=sk-...
export DATABASE_URL=postgresql://localhost/graphrag_test
python graph_embed.py --embedding-type base

# 3. Run example queries
psql -d graphrag_test -f test_project/queries/cypher_examples.sql
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GraphRAG System                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌────────────┐  │
│  │  Apache AGE     │    │   pgvector      │    │  GraphRAG  │  │
│  │  (Graph Store)  │◄──►│  (Embeddings)   │◄──►│  Functions │  │
│  │                 │    │                 │    │            │  │
│  │  • Nodes        │    │  • HNSW Index   │    │  • Search  │  │
│  │  • Edges        │    │  • Cosine Sim   │    │  • Extract │  │
│  │  • Cypher       │    │  • 1536 dims    │    │  • Traverse│  │
│  └─────────────────┘    └─────────────────┘    └────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Graph Schema (CRM Example)

### Nodes

| Node Type | Description | Key Properties |
|-----------|-------------|----------------|
| `Ticket` | Support tickets | subject, description, status, priority |
| `Customer` | Customer records | name, email, company, plan_type |
| `Product` | Product catalog | name, category, description |
| `Agent` | Support agents | name, team |
| `KBArticle` | Knowledge base | title, content, tags |
| `TicketMessage` | Ticket messages | message, sender_type |

### Edges (Relationships)

| Edge Type | From → To | Description |
|-----------|-----------|-------------|
| `CREATED_BY` | Ticket → Customer | Customer created the ticket |
| `ASSIGNED_TO` | Ticket → Agent | Agent handling the ticket |
| `ABOUT_PRODUCT` | Ticket → Product | Product the ticket concerns |
| `HAS_MESSAGE` | Ticket → TicketMessage | Messages on ticket |
| `DOCUMENTS` | KBArticle → Product | Article documents product |
| `REFERENCES` | Ticket → KBArticle | Ticket references article |
| `SIMILAR_TO` | Ticket → Ticket | Semantic similarity |

## Key Functions

### Graph Traversal

```sql
-- Get 1-hop neighbors
SELECT * FROM graphrag.get_node_neighborhood('Ticket', '1');

-- Get multi-hop context
SELECT * FROM graphrag.get_extended_context('Ticket', '1', 2, 50);

-- Build context text for embedding/LLM
SELECT graphrag.build_graph_context_text('Ticket', '1', 1);
```

### Vector Search

```sql
-- Basic vector search
SELECT * FROM graphrag.vector_search(query_embedding, 'Ticket', 'base', 5);

-- Graph-enhanced search (vector + connectivity boost)
SELECT * FROM graphrag.graph_enhanced_search(query_embedding, 'Ticket', 5);

-- Hybrid search (vector + property filters)
SELECT * FROM graphrag.hybrid_search(
    query_embedding, 'Ticket', 'base', 5,
    '{"status": "open", "priority": "high"}'::jsonb
);
```

### LLM Context

```sql
-- Extract subgraph for LLM context
SELECT graphrag.extract_subgraph_for_llm('Ticket', '1', 2, 20);

-- Path-based search with explanations
SELECT * FROM graphrag.path_similarity_search(
    query_embedding, 'KBArticle', 'Ticket', '1', 5
);
```

### Structural Similarity

```sql
-- Find tickets that share neighbors (same customer, product, etc.)
SELECT * FROM graphrag.find_structurally_similar('Ticket', '1', 'Ticket', 1, 5);
```

## GraphRAG vs ContextRAG

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| **Context Model** | Flat key-value attributes | Explicit graph relationships |
| **Relationships** | Implicit via context | Explicit typed edges |
| **Traversal** | None | Multi-hop Cypher queries |
| **Similarity** | Vector only | Vector + structural |
| **LLM Context** | Entity + attributes | Subgraph with paths |
| **Explainability** | Attribute weights | Path provenance |
| **Complexity** | Simple | More complex |
| **Performance** | Faster for basic RAG | Better for relationships |

### When to Use Each

**Use ContextRAG when:**
- Simple semantic search is sufficient
- Relationships are flat (metadata)
- Query latency is critical
- No multi-hop queries needed

**Use GraphRAG when:**
- Data has rich relationships
- Multi-hop discovery is valuable
- Path-based explanations needed
- Structural similarity matters
- Agent routing by expertise
- Customer journey analysis

## Directory Structure

```
GraphRAG/
├── extension/               # PostgreSQL extension
│   ├── graphrag.control
│   ├── graphrag--1.0.sql
│   └── Makefile
├── migrations/              # Standalone SQL migrations
│   ├── 001_setup_age_extension.sql
│   ├── 002_create_node_labels.sql
│   ├── 003_create_edge_labels.sql
│   ├── 004_create_vector_tables.sql
│   ├── 005_create_indexes.sql
│   └── 006_create_functions.sql
├── test_project/            # CRM example
│   ├── schema/
│   ├── data/
│   └── queries/
├── python/                  # Embedding tools
│   ├── embeddings.py
│   ├── graph_embed.py
│   └── requirements.txt
└── scripts/                 # Setup scripts
    ├── install.sh
    ├── setup_test_db.sh
    └── run_comparison.sh
```

## Prerequisites

- PostgreSQL 14+
- [Apache AGE](https://age.apache.org/) extension
- [pgvector](https://github.com/pgvector/pgvector) extension
- Python 3.8+ (for embeddings)
- OpenAI API key (for embeddings)

## Installation

### Option 1: Run Migrations

```bash
# Create database
createdb graphrag_test

# Install extensions
psql -d graphrag_test -c "CREATE EXTENSION age;"
psql -d graphrag_test -c "CREATE EXTENSION vector;"

# Run migrations
for f in migrations/*.sql; do psql -d graphrag_test -f "$f"; done
```

### Option 2: Install Extension

```bash
# Install extension files
./scripts/install.sh

# Create extension in database
psql -d graphrag_test -c "CREATE EXTENSION graphrag;"
```

## Example: Finding Relevant KB Articles

```sql
-- Starting from a support ticket, find relevant KB articles via:
-- 1. Same product
-- 2. Similar tickets that referenced them
-- 3. Semantic similarity

LOAD 'age';
SET search_path = ag_catalog, graphrag;

-- Multi-hop: Ticket → Product → KB Articles
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[:ABOUT_PRODUCT]->(p:Product)<-[:DOCUMENTS]-(kb:KBArticle)
    RETURN kb.title as article, p.name as via_product
$$) AS (article agtype, via_product agtype);

-- Multi-hop: Ticket → Customer → Other Tickets → KB Articles
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)-[:REFERENCES]->(kb:KBArticle)
    WHERE t <> t2 AND t2.status = 'resolved'
    RETURN DISTINCT kb.title as article, t2.subject as resolved_via
$$) AS (article agtype, resolved_via agtype);
```

## License

MIT License - See LICENSE file for details.
