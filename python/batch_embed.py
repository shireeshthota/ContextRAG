#!/usr/bin/env python3
"""
Batch Embedding Processor for ContextRAG

This script fetches entities from PostgreSQL that need embeddings,
generates embeddings using OpenAI, and stores them back in the database.
"""

import argparse
import os
import sys
from typing import Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv
from tqdm import tqdm

from embeddings import EmbeddingGenerator, format_embedding_for_postgres

# Load environment variables
load_dotenv()


def get_db_connection(connection_string: Optional[str] = None):
    """Get a database connection."""
    conn_str = connection_string or os.getenv(
        "DATABASE_URL", "postgresql://localhost/contextrag_test"
    )
    return psycopg2.connect(conn_str)


def fetch_unembedded_entities(
    conn,
    embedding_type: str = "base",
    entity_type: Optional[str] = None,
    limit: int = 100,
):
    """Fetch entities that need embeddings."""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT * FROM contextrag.get_unembedded_entities(%s, %s, %s)",
            (embedding_type, entity_type, limit),
        )
        return cur.fetchall()


def store_embedding(
    conn,
    entity_id: str,
    embedding_type: str,
    embedding: list,
    model_name: str,
):
    """Store an embedding in the database."""
    with conn.cursor() as cur:
        embedding_str = format_embedding_for_postgres(embedding)
        cur.execute(
            "SELECT contextrag.store_embedding(%s, %s, %s::vector, %s)",
            (entity_id, embedding_type, embedding_str, model_name),
        )
    conn.commit()


def process_entities(
    embedding_type: str = "base",
    entity_type: Optional[str] = None,
    limit: int = 100,
    batch_size: int = 10,
    connection_string: Optional[str] = None,
    dry_run: bool = False,
):
    """
    Process entities and generate embeddings.

    Args:
        embedding_type: Type of embedding to generate ('base' or 'local_context').
        entity_type: Optional filter for entity type.
        limit: Maximum number of entities to process.
        batch_size: Number of entities to embed in one API call.
        connection_string: PostgreSQL connection string.
        dry_run: If True, don't actually store embeddings.
    """
    # Initialize embedding generator
    try:
        generator = EmbeddingGenerator()
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    # Connect to database
    conn = get_db_connection(connection_string)

    try:
        # Fetch entities needing embeddings
        print(f"Fetching entities needing '{embedding_type}' embeddings...")
        entities = fetch_unembedded_entities(conn, embedding_type, entity_type, limit)

        if not entities:
            print("No entities found needing embeddings.")
            return

        print(f"Found {len(entities)} entities to process.")

        if dry_run:
            print("\n[DRY RUN] Would process these entities:")
            for e in entities[:5]:
                print(f"  - {e['entity_type']}/{e['source_id']}: {e['full_text'][:80]}...")
            if len(entities) > 5:
                print(f"  ... and {len(entities) - 5} more")
            return

        # Process in batches
        processed = 0
        errors = 0

        with tqdm(total=len(entities), desc="Generating embeddings") as pbar:
            for i in range(0, len(entities), batch_size):
                batch = entities[i : i + batch_size]
                texts = [e["full_text"] for e in batch]

                try:
                    # Generate embeddings for batch
                    embeddings = generator.generate_batch(texts, batch_size=batch_size)

                    # Store each embedding
                    for entity, embedding in zip(batch, embeddings):
                        store_embedding(
                            conn,
                            entity["entity_id"],
                            embedding_type,
                            embedding,
                            generator.model,
                        )
                        processed += 1
                        pbar.update(1)

                except Exception as e:
                    print(f"\nError processing batch: {e}")
                    errors += len(batch)
                    pbar.update(len(batch))

        print(f"\nCompleted: {processed} embeddings generated, {errors} errors.")

    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(
        description="Generate embeddings for ContextRAG entities"
    )
    parser.add_argument(
        "--embedding-type",
        choices=["base", "local_context"],
        default="base",
        help="Type of embedding to generate (default: base)",
    )
    parser.add_argument(
        "--entity-type",
        type=str,
        default=None,
        help="Filter by entity type (e.g., 'ticket', 'kb_article')",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Maximum number of entities to process (default: 100)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=10,
        help="Number of entities per API call (default: 10)",
    )
    parser.add_argument(
        "--database-url",
        type=str,
        default=None,
        help="PostgreSQL connection string (default: DATABASE_URL env var)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be processed without making changes",
    )

    args = parser.parse_args()

    process_entities(
        embedding_type=args.embedding_type,
        entity_type=args.entity_type,
        limit=args.limit,
        batch_size=args.batch_size,
        connection_string=args.database_url,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
