# GraphRAG Python Tools

Python utilities for generating and managing embeddings in GraphRAG.

## Setup

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env
# Edit .env with your OpenAI API key and database URL
```

## Environment Variables

```bash
OPENAI_API_KEY=sk-...
DATABASE_URL=postgresql://localhost/graphrag_test
```

## Scripts

### embeddings.py

Core embedding generation using OpenAI's API.

```python
from embeddings import EmbeddingGenerator, embed_text

# Quick usage
embedding = embed_text("Your text here")

# With configuration
generator = EmbeddingGenerator(model="text-embedding-3-small", dimensions=1536)
embedding = generator.generate("Your text here")

# Batch processing
embeddings = generator.generate_batch(["Text 1", "Text 2", "Text 3"])
```

### graph_embed.py

Graph-aware embedding processor for GraphRAG nodes.

**Embedding Types:**
- `base`: Pure node content (subject, description, etc.)
- `neighborhood`: Node content + 1-hop neighbor context from the graph

```bash
# Generate base embeddings for all Ticket nodes
python graph_embed.py --node-label Ticket --embedding-type base

# Generate neighborhood embeddings (includes graph context)
python graph_embed.py --node-label Ticket --embedding-type neighborhood

# Process all node types
python graph_embed.py --embedding-type base

# Dry run to see what would be processed
python graph_embed.py --node-label Ticket --dry-run

# Full options
python graph_embed.py \
    --node-label Ticket \
    --embedding-type neighborhood \
    --limit 100 \
    --batch-size 10 \
    --database-url "postgresql://localhost/graphrag_test"
```

## Embedding Types Explained

### Base Embeddings

Pure content embeddings based only on the node's properties:

| Node Type | Text Embedded |
|-----------|---------------|
| Ticket | `subject. description` |
| Customer | `name (email). Company: company. Plan: plan_type` |
| Product | `name: description` |
| Agent | `name - team team` |
| KBArticle | `title. content. Tags: tags` |
| TicketMessage | `message` |

### Neighborhood Embeddings

Content + graph context. For each node, we append information about its relationships:

```
SSO Login Issue. After changing my password...

Relationships:
->[CREATED_BY]-> Customer: John Smith
->[ASSIGNED_TO]-> Agent: Tom Anderson
->[ABOUT_PRODUCT]-> Product: SecureAuth
->[REFERENCES]-> KBArticle: How to configure SSO with Azure AD
```

This allows similarity searches to find tickets that are structurally similar (same customer, same product, same agent) in addition to semantically similar.

## Workflow

1. **Populate the graph:**
   ```bash
   psql -d graphrag_test -f test_project/data/create_graph.sql
   ```

2. **Generate base embeddings:**
   ```bash
   python graph_embed.py --embedding-type base
   ```

3. **Generate neighborhood embeddings:**
   ```bash
   python graph_embed.py --embedding-type neighborhood
   ```

4. **Run searches:**
   ```sql
   -- Vector search on base embeddings
   SELECT * FROM graphrag.vector_search(query_embedding, 'Ticket', 'base', 5);

   -- Graph-enhanced search (vector + connectivity)
   SELECT * FROM graphrag.graph_enhanced_search(query_embedding, 'Ticket', 5);
   ```

## Comparison with ContextRAG

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| **Context Model** | Flat key-value attributes | Graph relationships |
| **Embedding Text** | Entity content + weighted context attributes | Node content + neighbor summaries |
| **Structural Similarity** | None | Neighbors share connections |
| **Multi-hop** | No | Yes (via Cypher traversal) |
