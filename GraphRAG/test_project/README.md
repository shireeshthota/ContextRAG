# GraphRAG Test Project: Support Ticket System

This test project demonstrates GraphRAG using a CRM-style support ticket system. The same data is used in the companion ContextRAG project for comparison.

## Data Model

### Relational Tables (support schema)

```
support.customers      - Customer records (8 rows)
support.products       - Product catalog (5 rows)
support.agents         - Support agents (4 rows)
support.tickets        - Support tickets (8 rows)
support.ticket_messages - Ticket messages (12 rows)
support.kb_articles    - Knowledge base (5 rows)
```

### Graph Representation

The relational data is converted to a property graph:

```
Nodes:
  - 8 Customer nodes
  - 5 Product nodes
  - 4 Agent nodes
  - 8 Ticket nodes
  - 12 TicketMessage nodes
  - 5 KBArticle nodes

Edges:
  - CREATED_BY: Ticket -> Customer (8 edges)
  - ASSIGNED_TO: Ticket -> Agent (6 edges)
  - ABOUT_PRODUCT: Ticket -> Product (8 edges)
  - HAS_MESSAGE: Ticket -> TicketMessage (12 edges)
  - DOCUMENTS: KBArticle -> Product (5 edges)
  - REFERENCES: Ticket -> KBArticle (4 edges, semantic)
```

## Setup

```bash
# From GraphRAG root directory
./scripts/setup_test_db.sh graphrag_test
```

This will:
1. Create the database
2. Install extensions (age, vector)
3. Run all migrations
4. Create the support schema
5. Load seed data
6. Populate the graph

## Generating Embeddings

```bash
cd ../python
pip install -r requirements.txt
export OPENAI_API_KEY=sk-...
export DATABASE_URL=postgresql://localhost/graphrag_test

# Generate base embeddings (node content only)
python graph_embed.py --embedding-type base

# Generate neighborhood embeddings (content + graph context)
python graph_embed.py --embedding-type neighborhood
```

## Running Queries

### Basic Cypher Examples

```bash
psql -d graphrag_test -f queries/cypher_examples.sql
```

Demonstrates:
- Node and edge counts
- Basic pattern matching
- Multi-hop traversals
- Aggregations
- Complex patterns

### Graph-Enhanced Search

```bash
psql -d graphrag_test -f queries/graph_search_examples.sql
```

Demonstrates:
- Neighborhood context extraction
- Subgraph extraction for LLM
- Structural similarity search
- Agent expertise discovery
- Customer journey analysis

### Comparison Tests

```bash
psql -d graphrag_test -f queries/comparison_tests.sql
```

Demonstrates 9 test cases comparing GraphRAG vs ContextRAG:
1. Simple semantic search (TIE)
2. Attribute-filtered search (ContextRAG)
3. Find similar tickets - same customer (GraphRAG)
4. Multi-hop discovery (GraphRAG)
5. Agent expertise routing (GraphRAG)
6. Path-based recommendations (GraphRAG)
7. Structural similarity (GraphRAG)
8. LLM context generation (depends)
9. Query complexity/performance (depends)

## Key Differences from ContextRAG

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| Customer relationship | `context_value: 'John Smith'` | `(t)-[:CREATED_BY]->(c:Customer)` |
| Product relationship | `context_value: 'SecureAuth'` | `(t)-[:ABOUT_PRODUCT]->(p:Product)` |
| Finding related tickets | Compare context attributes | Traverse shared neighbors |
| KB article discovery | Semantic similarity only | Similarity + path traversal |

## Sample Queries

### Find tickets from the same customer

```sql
-- GraphRAG
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t1:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)
    WHERE t1 <> t2
    RETURN t2.subject, c.name
$$) AS (subject agtype, customer agtype);
```

### Find KB articles via customer's resolved tickets

```sql
-- GraphRAG (multi-hop)
SELECT * FROM ag_catalog.cypher('support_graph', $$
    MATCH (t:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)-[:REFERENCES]->(kb:KBArticle)
    WHERE t <> t2 AND t2.status = 'resolved'
    RETURN DISTINCT kb.title, t2.subject as via_ticket
$$) AS (article agtype, via_ticket agtype);
```

### Get LLM context with relationships

```sql
SELECT graphrag.extract_subgraph_for_llm('Ticket', '1', 2, 15);
```

Output:
```
=== SUBGRAPH CONTEXT ===

## Primary Entity
- Ticket (1): {"subject": "Unable to login with SSO...", ...}

## 1-hop Neighbors
- Customer (1): {"name": "John Smith", ...}
  Path: Ticket -[CREATED_BY]- Customer
- Agent (1): {"name": "Tom Anderson", ...}
  Path: Ticket -[ASSIGNED_TO]- Agent
- Product (2): {"name": "SecureAuth", ...}
  Path: Ticket -[ABOUT_PRODUCT]- Product
...
```
