"""
OpenAI Embedding Generation for GraphRAG

This module provides functions to generate embeddings using OpenAI's API.
Reused from ContextRAG with minor adaptations for graph-aware embeddings.
"""

import os
from typing import List, Optional
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Default model for embeddings
DEFAULT_MODEL = "text-embedding-3-small"
DEFAULT_DIMENSIONS = 1536


class EmbeddingGenerator:
    """Generate embeddings using OpenAI's API."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = DEFAULT_MODEL,
        dimensions: int = DEFAULT_DIMENSIONS,
    ):
        """
        Initialize the embedding generator.

        Args:
            api_key: OpenAI API key. If not provided, uses OPENAI_API_KEY env var.
            model: The embedding model to use.
            dimensions: The embedding dimensions (1536 for text-embedding-3-small).
        """
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError(
                "OpenAI API key is required. "
                "Set OPENAI_API_KEY environment variable or pass api_key parameter."
            )

        self.client = OpenAI(api_key=self.api_key)
        self.model = model
        self.dimensions = dimensions

    def generate(self, text: str) -> List[float]:
        """
        Generate an embedding for a single text.

        Args:
            text: The text to embed.

        Returns:
            A list of floats representing the embedding vector.
        """
        # Truncate text if too long (OpenAI has a token limit)
        max_chars = 8000 * 4  # Approximate: 4 chars per token, 8000 token limit
        if len(text) > max_chars:
            text = text[:max_chars]

        response = self.client.embeddings.create(
            input=text,
            model=self.model,
            dimensions=self.dimensions,
        )

        return response.data[0].embedding

    def generate_batch(
        self, texts: List[str], batch_size: int = 100
    ) -> List[List[float]]:
        """
        Generate embeddings for multiple texts.

        Args:
            texts: List of texts to embed.
            batch_size: Number of texts to process per API call.

        Returns:
            A list of embedding vectors.
        """
        embeddings = []
        max_chars = 8000 * 4

        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]

            # Truncate texts in batch
            batch = [t[:max_chars] if len(t) > max_chars else t for t in batch]

            response = self.client.embeddings.create(
                input=batch,
                model=self.model,
                dimensions=self.dimensions,
            )

            # Sort by index to maintain order
            sorted_data = sorted(response.data, key=lambda x: x.index)
            embeddings.extend([d.embedding for d in sorted_data])

        return embeddings


def format_embedding_for_postgres(embedding: List[float]) -> str:
    """
    Format an embedding vector for PostgreSQL insertion.

    Args:
        embedding: The embedding vector.

    Returns:
        A string formatted for PostgreSQL vector type.
    """
    return "[" + ",".join(str(x) for x in embedding) + "]"


# Convenience function for quick embedding generation
def embed_text(text: str, api_key: Optional[str] = None) -> List[float]:
    """
    Generate an embedding for a single text (convenience function).

    Args:
        text: The text to embed.
        api_key: Optional OpenAI API key.

    Returns:
        The embedding vector.
    """
    generator = EmbeddingGenerator(api_key=api_key)
    return generator.generate(text)


if __name__ == "__main__":
    # Example usage
    import sys

    if len(sys.argv) < 2:
        print("Usage: python embeddings.py 'text to embed'")
        sys.exit(1)

    text = sys.argv[1]
    try:
        generator = EmbeddingGenerator()
        embedding = generator.generate(text)
        print(f"Generated embedding with {len(embedding)} dimensions")
        print(f"First 5 values: {embedding[:5]}")
        print(f"\nPostgreSQL format (first 100 chars):")
        pg_format = format_embedding_for_postgres(embedding)
        print(pg_format[:100] + "...")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)
