# ContextRAG Python Helpers

Python utilities for generating embeddings using OpenAI's API and storing them in PostgreSQL.

## Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export OPENAI_API_KEY=your_api_key_here
export DATABASE_URL=postgresql://user:pass@localhost/dbname
```

Or create a `.env` file:
```
OPENAI_API_KEY=your_api_key_here
DATABASE_URL=postgresql://localhost/contextrag_test
```

## Usage

### Batch Embedding Generation

Process all entities needing embeddings:

```bash
# Generate base embeddings
python batch_embed.py --embedding-type base

# Generate local_context embeddings (includes context attributes)
python batch_embed.py --embedding-type local_context

# Filter by entity type
python batch_embed.py --entity-type ticket --limit 50

# Dry run to preview
python batch_embed.py --dry-run
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--embedding-type` | `base` or `local_context` | `base` |
| `--entity-type` | Filter by type (ticket, kb_article, etc.) | None (all) |
| `--limit` | Max entities to process | 100 |
| `--batch-size` | Entities per API call | 10 |
| `--database-url` | PostgreSQL connection string | `DATABASE_URL` env |
| `--dry-run` | Preview without changes | False |

### Direct Embedding Generation

```python
from embeddings import EmbeddingGenerator, embed_text

# Quick embedding
embedding = embed_text("How do I reset my password?")

# With generator instance
generator = EmbeddingGenerator()
embedding = generator.generate("Some text to embed")
embeddings = generator.generate_batch(["text1", "text2", "text3"])
```

### Test Single Text

```bash
python embeddings.py "How do I reset my password?"
```

## Embedding Types

### Base Embeddings
Generated from the entity's base content (subject, description, etc.). Best for semantic search on the raw content.

```bash
python batch_embed.py --embedding-type base
```

### Local Context Embeddings
Generated from base content + context attributes. Captures additional metadata like status, priority, customer info.

```bash
python batch_embed.py --embedding-type local_context
```

## Integration Example

```python
import psycopg2
from embeddings import EmbeddingGenerator, format_embedding_for_postgres

# Generate query embedding
generator = EmbeddingGenerator()
query_embedding = generator.generate("password reset not working")

# Search in PostgreSQL
conn = psycopg2.connect("postgresql://localhost/mydb")
cur = conn.cursor()

embedding_str = format_embedding_for_postgres(query_embedding)
cur.execute("""
    SELECT * FROM contextrag.vector_search(
        %s::vector,
        'base',
        5,
        'kb_article'
    )
""", (embedding_str,))

results = cur.fetchall()
for row in results:
    print(f"Score: {row[-1]:.3f} - {row[4]}")  # similarity and base_content
```

## Technical Details

- **Model**: `text-embedding-3-large` (3072 dimensions)
- **Max Input**: ~8000 tokens per text
- **Batch Processing**: Up to 100 texts per API call
- **Rate Limits**: Respects OpenAI rate limits via the SDK

## Troubleshooting

### "No module named 'openai'"
```bash
pip install openai
```

### "OpenAI API key is required"
```bash
export OPENAI_API_KEY=sk-...
```

### Connection refused
Ensure PostgreSQL is running and DATABASE_URL is correct:
```bash
export DATABASE_URL=postgresql://user:password@localhost:5432/dbname
```
