# ContextRAG Test Project: Support Ticket System

This test project demonstrates ContextRAG with a support ticket CRM system. It includes customers, products, support agents, tickets, and knowledge base articles.

## Schema Overview

| Table | Description |
|-------|-------------|
| `support.customers` | Customer records with plans |
| `support.products` | Product catalog |
| `support.agents` | Support team members |
| `support.tickets` | Support tickets (main entity) |
| `support.ticket_messages` | Ticket conversation history |
| `support.kb_articles` | Knowledge base articles |

## Setup Instructions

### 1. Prerequisites

```bash
# Ensure PostgreSQL is running with pgvector installed
psql -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### 2. Install ContextRAG Extension

```bash
# Option A: Using the extension
cd ../extension
make && sudo make install
psql -d your_database -c "CREATE EXTENSION contextrag;"

# Option B: Using migrations
psql -d your_database -f ../migrations/001_create_core_tables.sql
psql -d your_database -f ../migrations/002_create_indexes.sql
psql -d your_database -f ../migrations/003_create_functions.sql
```

### 3. Create Test Schema and Data

```bash
# Create the support schema and tables
psql -d your_database -f schema/support_tickets.sql

# Insert seed data
psql -d your_database -f data/seed_data.sql

# Register entities with ContextRAG
psql -d your_database -f data/register_entities.sql
```

### 4. Generate Embeddings

```bash
# Install Python dependencies
cd ../python
pip install -r requirements.txt

# Set your OpenAI API key
export OPENAI_API_KEY=your_key_here

# Generate embeddings for all entities
python batch_embed.py --embedding-type base
python batch_embed.py --embedding-type local_context
```

### 5. Run Search Queries

```bash
# Open psql and run example queries
psql -d your_database -f queries/search_examples.sql
```

## Entity Registration

The `register_entities.sql` script:
1. Registers each support ticket as an entity
2. Registers each KB article as an entity
3. Adds context attributes:
   - **Tickets**: status, priority, category, customer info, product, agent
   - **KB Articles**: category, product, tags

## Example Searches

### Find Related KB Articles for a Ticket

```sql
-- Get ticket's embedding and find similar KB articles
WITH ticket_emb AS (
    SELECT emb.embedding
    FROM contextrag.entity_embeddings emb
    JOIN contextrag.entities e ON e.id = emb.entity_id
    WHERE e.source_table = 'tickets' AND e.source_id = '1'
      AND emb.embedding_type = 'base'
)
SELECT * FROM contextrag.vector_search(
    (SELECT embedding FROM ticket_emb),
    'base', 3, 'kb_article'
);
```

### Find High Priority Open Tickets

```sql
SELECT * FROM contextrag.context_aware_search(
    query_embedding,
    'base', 10, 'ticket',
    'priority', 'ticket_priority', 'high'
);
```

### Multi-Embedding Search

```sql
SELECT * FROM contextrag.multi_embedding_search(
    query_embedding,
    0.7,  -- base weight
    0.3,  -- context weight
    10
);
```

## Data Summary

After running the seed scripts:
- 8 customers
- 5 products
- 4 agents
- 8 tickets
- 12 ticket messages
- 5 KB articles

Each ticket has 5-8 context attributes, and each KB article has 4-8 context attributes (including tags).
