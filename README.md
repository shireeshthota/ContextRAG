# ContextRAG

A PostgreSQL extension for **Contextual Row-based RAG** (Retrieval-Augmented Generation) that enriches database rows with optional contextual layers for more accurate, explainable retrieval.

## Overview

ContextRAG bridges the gap between traditional database queries and semantic search by:

1. **Registering entities** from your existing tables into a unified searchable registry
2. **Adding context** attributes that enrich entities with metadata (status, priority, relationships)
3. **Generating multiple embeddings** per entity (base content, content + context)
4. **Searching** with vector similarity, SQL filters, or both combined

## Quick Start

### Prerequisites

- PostgreSQL 17+
- [pgvector](https://github.com/pgvector/pgvector) extension
- Python 3.8+ (for embedding generation)
- OpenAI API key

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/contextrag.git
cd contextrag

# Set up test database
./scripts/setup_test_db.sh contextrag_test

# Set up Python environment
cd python
pip install -r requirements.txt
export OPENAI_API_KEY=your_key_here

# Generate embeddings
python batch_embed.py --embedding-type base
python batch_embed.py --embedding-type local_context
```

### Basic Usage

```sql
-- Register an entity from your data
SELECT contextrag.register_entity(
    'support',           -- source schema
    'tickets',           -- source table
    '123',               -- source id
    'ticket',            -- entity type
    '{"subject": "Cannot login", "description": "Password reset not working"}'
);

-- Add context attributes
SELECT contextrag.add_context(entity_id, 'status', 'ticket_status', 'open');
SELECT contextrag.add_context(entity_id, 'priority', 'level', 'high', 0.9);

-- Search by vector similarity
SELECT * FROM contextrag.vector_search(query_embedding, 'base', 10, 'ticket');

-- Hybrid search with filters
SELECT * FROM contextrag.hybrid_search(
    query_embedding,
    'base',
    10,
    'ticket',
    '{"customer_plan": "enterprise"}'::JSONB
);
```

## Project Structure

```
ContextRAG/
├── extension/                    # PostgreSQL extension files
│   ├── contextrag.control       # Extension metadata
│   ├── contextrag--1.0.sql      # Schema + functions
│   └── Makefile                 # PGXS build
├── migrations/                   # Standalone SQL migrations
│   ├── 001_create_core_tables.sql
│   ├── 002_create_indexes.sql
│   └── 003_create_functions.sql
├── test_project/                 # Example CRM application
│   ├── schema/                  # Sample tables
│   ├── data/                    # Seed data
│   └── queries/                 # Example searches
├── python/                       # Embedding generation
│   ├── embeddings.py           # OpenAI API wrapper
│   └── batch_embed.py          # Batch processor
└── scripts/                      # Setup scripts
    ├── install.sh
    └── setup_test_db.sh
```

## Core Concepts

### Entities

Entities are records in the `contextrag.entities` table that link to your source data:

| Column | Description |
|--------|-------------|
| `source_schema` | Schema of source table |
| `source_table` | Name of source table |
| `source_id` | Primary key in source table |
| `entity_type` | Classification (ticket, article, etc.) |
| `base_content` | JSONB content for embeddings |

### Context

Context attributes enrich entities with additional information:

```sql
SELECT contextrag.add_context(
    entity_id,
    'category',          -- context_type
    'topic',             -- context_key
    'authentication',    -- context_value
    0.9,                 -- weight (importance)
    NULL,                -- metadata
    '2024-12-31'::TIMESTAMPTZ  -- expires_at (optional)
);
```

### Embedding Types

| Type | Description | Use Case |
|------|-------------|----------|
| `base` | Raw content embedding | Semantic search on content |
| `local_context` | Content + context | Context-aware search |

## Search Functions

### Vector Search

```sql
SELECT * FROM contextrag.vector_search(
    query_embedding,     -- vector(3072)
    'base',              -- embedding_type
    10,                  -- limit
    'ticket'             -- entity_type filter (optional)
);
```

### Multi-Embedding Search

Combines base and context embeddings with weighted scoring:

```sql
SELECT * FROM contextrag.multi_embedding_search(
    query_embedding,
    0.7,                 -- base_weight
    0.3,                 -- context_weight
    10
);
```

### Hybrid Search

Vector similarity with SQL filters:

```sql
SELECT * FROM contextrag.hybrid_search(
    query_embedding,
    'base',
    10,
    'ticket',
    '{"priority": "high"}'::JSONB,  -- metadata filter
    0.5                              -- min_similarity
);
```

### Context-Aware Search

Filter by context attributes:

```sql
SELECT * FROM contextrag.context_aware_search(
    query_embedding,
    'base',
    10,
    'ticket',
    'status',            -- context_type
    'ticket_status',     -- context_key
    'open'               -- context_value
);
```

## Technical Details

### Embedding Configuration

- **Model**: OpenAI `text-embedding-3-large`
- **Dimensions**: 3072
- **HNSW Parameters**: m=16, ef_construction=64

### Index Strategy

Separate HNSW indexes per embedding type (partial indexes) ensure:
- No mixing of base and context embedding semantics
- Optimal performance for filtered queries
- Better recall for type-specific searches

### Content Change Detection

MD5 hash of `base_content` enables efficient detection of stale embeddings:

```sql
SELECT * FROM contextrag.get_stale_entities('base', 100);
```

## Test Project

The included test project demonstrates a support ticket system:

- **Customers**: 8 sample customers with different plans
- **Products**: 5 software/service products
- **Agents**: 4 support team members
- **Tickets**: 8 support tickets with various statuses
- **KB Articles**: 5 knowledge base articles

See `test_project/README.md` for setup instructions.

## Roadmap

### Phase 1 (Current)
- [x] Entity registry with source linking
- [x] Local context attributes
- [x] Base and local_context embeddings
- [x] Vector, hybrid, and context-aware search

### Phase 2 (Planned)
- [ ] Entity edges table for relationships
- [ ] Graph traversal functions
- [ ] Neighborhood expansion

### Phase 3 (Future)
- [ ] Propagated context embeddings
- [ ] Context decay rules
- [ ] Transitive context propagation

## Test Case Walkthrough: Base vs Local Context Embeddings

This walkthrough explains the core architecture of ContextRAG by tracing a single ticket through entity registration, context enrichment, and dual-embedding generation. It demonstrates why splitting content from context — and embedding them separately — produces fundamentally better search results than standard RAG.

### The Problem ContextRAG Solves

Standard RAG embeds text and searches by text similarity. But in a real application, two pieces of content that look textually different can be deeply related through **structured attributes** — and two pieces that look textually similar can be irrelevant to each other because of their **context**.

Consider these two support tickets from the test project:

| Ticket | Subject | Product | Priority | Customer Plan |
|--------|---------|---------|----------|---------------|
| 1 | Unable to login with SSO after password change | SecureAuth | high | enterprise |
| 6 | Password reset email not received | SecureAuth | medium | free |

A base embedding captures that both are authentication issues on SecureAuth. But it has **no idea** that one is from a $100K/year enterprise account and the other is from a free user. A support agent searching for "urgent enterprise auth issues" needs that distinction.

ContextRAG solves this by splitting each entity into two layers: **what it says** (`entities` table) and **what it means in context** (`entity_context` table).

### Layer 1: Entity Registration (`contextrag.entities`)

When `register_entities.sql` runs, each ticket is registered:

```sql
v_entity_id := contextrag.register_entity(
    'support',           -- source_schema
    'tickets',           -- source_table
    t.id::TEXT,          -- source_id
    'ticket',            -- entity_type
    jsonb_build_object(  -- base_content (the embeddable text)
        'subject', t.subject,
        'description', t.description,
        'text', t.subject || '. ' || t.description
    ),
    jsonb_build_object(  -- metadata (for SQL-level filtering)
        'product', t.product_name,
        'customer_plan', t.customer_plan
    )
);
```

This does three things:

**1. Creates a universal identity layer.** The `(source_schema, source_table, source_id)` triple is a pointer back to the original row in `support.tickets`. ContextRAG never copies or owns the source data — it's a **bridge**. Any table in any schema can register entities. Tickets and KB articles, despite living in completely different tables with different columns, become peers in the same entity registry.

**2. Extracts embeddable content into `base_content`.** This is the text that will be turned into the **base embedding** — the pure semantic representation. The `'text'` key concatenates subject + description into a single string for the embedding model. The JSONB format keeps the structured fields available (for display in search results via `base_content->>'subject'`) while the `'text'` key provides the flat string for embedding.

**3. Stores filterable metadata.** The `metadata` JSONB column (`{"product": "SecureAuth", "customer_plan": "enterprise"}`) is for **SQL-level pre-filtering** via `hybrid_search()`. This is NOT embedded — it's used with `@>` (JSONB containment) to narrow the search space BEFORE vector similarity runs. This is the "hybrid" in hybrid search.

### Layer 2: Context Attributes (`contextrag.entity_context`)

This is where ContextRAG diverges from standard RAG. Each `add_context()` call attaches a **weighted, typed, key-value attribute** to the entity:

```sql
-- For ticket 1 (SSO login, enterprise, high priority):
PERFORM contextrag.add_context(v_entity_id, 'priority', 'ticket_priority', 'high',       0.8);
PERFORM contextrag.add_context(v_entity_id, 'category', 'ticket_category', 'technical',  1.0);
PERFORM contextrag.add_context(v_entity_id, 'customer', 'plan_type',      'enterprise',  0.8);
PERFORM contextrag.add_context(v_entity_id, 'product',  'product_name',   'SecureAuth',  0.9);
PERFORM contextrag.add_context(v_entity_id, 'agent',    'assigned_agent', 'Tom Anderson', 0.5);
```

Each attribute has three dimensions of meaning:

#### The three-part key: `context_type` / `context_key` / `context_value`

| context_type | context_key | context_value | What it captures |
|---|---|---|---|
| `priority` | `ticket_priority` | `urgent` | How important this ticket is |
| `customer` | `plan_type` | `enterprise` | What kind of customer filed it |
| `customer` | `customer_company` | `Acme Corporation` | Which specific customer |
| `product` | `product_name` | `SecureAuth` | Which product it relates to |
| `agent` | `assigned_agent` | `Tom Anderson` | Who is working on it |

The `context_type` groups related attributes (all customer info under `'customer'`). The `context_key` names the specific attribute. The `context_value` holds the value. This three-level structure enables both broad filtering ("show me all customer context") and precise filtering ("where plan_type = enterprise").

#### The weight: signal importance

Each attribute gets a weight from 0.0 to 1.0:

```
category:      1.0  — What the ticket IS about. Highest signal.
product:       0.9  — Which product. Nearly as important.
priority:      0.8 (high), 1.0 (urgent) — Urgency scales the weight.
status:        0.9 (in_progress), 0.3 (closed) — Active tickets matter more.
plan_type:     0.8  — Customer tier. Important for routing.
customer_name: 0.7  — Who filed it. Moderate signal.
company:       0.6  — Which organization. Less specific.
agent_team:    0.6  — General team. Moderate signal.
agent_name:    0.5  — Specific person. Lowest signal.
```

These weights serve **two purposes**:

**Purpose 1: Ordering in `build_context_text()`.** When context is converted to text for the `local_context` embedding, attributes are ordered by `weight DESC`. The embedding model pays more attention to text that appears earlier. So for ticket 1, the context text becomes:

```
category: ticket_category = technical; priority: ticket_priority = high;
product: product_name = SecureAuth; status: ticket_status = in_progress;
customer: plan_type = enterprise; customer: customer_name = John Smith;
customer: customer_company = Acme Corporation; agent: agent_team = technical;
agent: assigned_agent = Tom Anderson
```

Category and product appear first (weight 1.0, 0.9) — they dominate the embedding. Agent name appears last (weight 0.5) — it's a minor signal.

**Purpose 2: Potential runtime ranking.** The weights are stored and queryable. A custom search could weight results by the importance of matching context attributes.

#### Temporal context with `expires_at`

The context table has an `expires_at` column for **temporal context** — attributes that are true now but won't be later. For example, a ticket's status changes from `open` to `resolved`. Rather than deleting and re-inserting, you could set an expiration. `build_context_text()` automatically filters out expired context.

### How the Two Layers Produce Two Embeddings

When `batch_embed.py` runs, it generates **two different embeddings** per entity:

#### `base` embedding — pure content

```
"Unable to login with SSO after password change. After changing my corporate
password, I can no longer login to SecureAuth using SSO. I get an error message
saying 'Authentication failed'..."
```

This captures **what the ticket says**. Two tickets with similar text will be close in this embedding space regardless of who filed them or their priority.

#### `local_context` embedding — content + context

```
"Unable to login with SSO after password change. After changing my corporate
password, I can no longer login to SecureAuth using SSO...

Context:
category: ticket_category = technical; priority: ticket_priority = high;
product: product_name = SecureAuth; status: ticket_status = in_progress;
customer: plan_type = enterprise; customer: customer_name = John Smith;
customer: customer_company = Acme Corporation; agent: agent_team = technical;
agent: assigned_agent = Tom Anderson"
```

This captures **what the ticket says PLUS what it means in context**. Now two tickets that are both enterprise/high-priority/SecureAuth/technical will be closer together in this embedding space than they would be in the base space — even if their text describes different problems.

### The Concrete Effect on Search

Take ticket 1 (SSO login) and ticket 5 (API rate limit exceeded):

In **base** embedding space: **distant**. One is about authentication, the other about rate limiting. Different vocabulary, different problems.

In **local_context** embedding space: **closer**. Both share: `enterprise` plan, `high` priority, `technical` category, and both agents are on the `technical` team. The context text pulls them toward each other.

This is exactly what `multi_embedding_search()` exploits — it blends both signals with configurable weights (e.g., 60% base + 40% context) to produce rankings that balance "similar content" with "similar situation."

### The KB Article Pattern

KB articles follow the same two-layer pattern but with different context attributes:

```sql
-- Entity: the article text
register_entity('support', 'kb_articles', '1', 'kb_article',
    {"title": "How to configure SSO with Azure AD", "content": "...", "text": "..."})

-- Context: structured attributes
add_context(id, 'category', 'article_category', 'how_to',           1.0)
add_context(id, 'product',  'product_name',     'SecureAuth',       0.9)
add_context(id, 'tag',      'sso',              'sso',              0.7)
add_context(id, 'tag',      'azure',            'azure',            0.7)
add_context(id, 'tag',      'saml',             'saml',             0.7)
add_context(id, 'tag',      'authentication',   'authentication',   0.7)
```

Because tickets and KB articles share the same `product_name` context key and the same context embedding approach, a `local_context` search for ticket 1 (SecureAuth, enterprise, technical) will naturally boost KB articles that are also tagged with SecureAuth — even if the article's text is about SSO configuration steps and the ticket's text is about a login error. The shared context pulls them together in embedding space.

### Summary

`entities` stores **WHAT** something is (embeddable text + filterable metadata). `entity_context` stores the **MEANING AROUND IT** (weighted structured attributes). The two-embedding design lets you search by content, by context, or by any blend of both — with every search function leveraging HNSW indexes and cosine similarity for sub-millisecond retrieval at scale.

## License

MIT License
