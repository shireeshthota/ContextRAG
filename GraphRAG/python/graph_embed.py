#!/usr/bin/env python3
"""
Graph-Aware Embedding Processor for GraphRAG

This script generates embeddings for graph nodes with two embedding types:
- 'base': Pure node content (subject, description, etc.)
- 'neighborhood': Node content + 1-hop neighbor context from the graph

The neighborhood embedding captures the structural context of each node,
enabling similarity searches that consider graph relationships.
"""

import argparse
import os
import sys
from typing import Optional, List, Dict, Any

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
        "DATABASE_URL", "postgresql://localhost/graphrag_test"
    )
    return psycopg2.connect(conn_str)


def ensure_age_loaded(conn):
    """Ensure AGE extension is loaded for the session."""
    with conn.cursor() as cur:
        cur.execute("LOAD 'age';")
        cur.execute("SET search_path = ag_catalog, graphrag, support, \"$user\", public;")
    conn.commit()


def get_node_text(node_label: str, properties: Dict[str, Any]) -> str:
    """
    Build embeddable text from node properties based on node type.

    Args:
        node_label: The type of node (Ticket, Customer, etc.)
        properties: The node's properties dict

    Returns:
        A text string suitable for embedding
    """
    if node_label == "Ticket":
        return f"{properties.get('subject', '')}. {properties.get('description', '')}"
    elif node_label == "Customer":
        company = properties.get('company', '')
        plan = properties.get('plan_type', '')
        return f"{properties.get('name', '')} ({properties.get('email', '')}). Company: {company}. Plan: {plan}"
    elif node_label == "Product":
        return f"{properties.get('name', '')}: {properties.get('description', '')}"
    elif node_label == "Agent":
        return f"{properties.get('name', '')} - {properties.get('team', '')} team"
    elif node_label == "KBArticle":
        tags = properties.get('tags', '')
        return f"{properties.get('title', '')}. {properties.get('content', '')}. Tags: {tags}"
    elif node_label == "TicketMessage":
        return properties.get('message', '')
    else:
        # Fallback: concatenate all string properties
        return " ".join(str(v) for v in properties.values() if isinstance(v, str))


def get_neighborhood_context(conn, node_label: str, source_id: str) -> str:
    """
    Get the neighborhood context for a node as text.

    This includes the node's direct neighbors and the relationship types,
    which provides structural context for the embedding.

    Args:
        conn: Database connection
        node_label: The node's label
        source_id: The node's source_id

    Returns:
        A text description of the node's neighborhood
    """
    context_parts = []

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # Get neighbors using GraphRAG function
        try:
            cur.execute(
                "SELECT * FROM graphrag.get_node_neighborhood(%s, %s)",
                (node_label, source_id)
            )
            neighbors = cur.fetchall()

            for neighbor in neighbors:
                direction = "->" if neighbor['edge_direction'] == 'outgoing' else "<-"
                edge_type = neighbor['edge_type']
                neighbor_label = neighbor['neighbor_label']
                neighbor_id = neighbor['neighbor_source_id']

                # Get a summary of the neighbor
                neighbor_props = neighbor.get('neighbor_properties', {})
                if isinstance(neighbor_props, str):
                    import json
                    neighbor_props = json.loads(neighbor_props) if neighbor_props else {}

                neighbor_summary = ""
                if neighbor_label == "Customer":
                    neighbor_summary = neighbor_props.get('name', '')
                elif neighbor_label == "Product":
                    neighbor_summary = neighbor_props.get('name', '')
                elif neighbor_label == "Agent":
                    neighbor_summary = neighbor_props.get('name', '')
                elif neighbor_label == "KBArticle":
                    neighbor_summary = neighbor_props.get('title', '')
                elif neighbor_label == "Ticket":
                    neighbor_summary = neighbor_props.get('subject', '')[:50]

                context_parts.append(
                    f"{direction}[{edge_type}]{direction} {neighbor_label}: {neighbor_summary}"
                )

        except Exception as e:
            # If the function doesn't exist yet, return empty context
            print(f"Warning: Could not get neighborhood for {node_label}/{source_id}: {e}")
            return ""

    return "\n".join(context_parts)


def fetch_nodes_for_embedding(
    conn,
    node_label: str,
    embedding_type: str = "base",
    limit: int = 100,
) -> List[Dict[str, Any]]:
    """
    Fetch nodes that need embeddings.

    Args:
        conn: Database connection
        node_label: The type of nodes to fetch
        embedding_type: 'base' or 'neighborhood'
        limit: Maximum number of nodes to fetch

    Returns:
        List of nodes with their properties
    """
    nodes = []

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # Get all nodes of this type from the graph
        cur.execute(f"""
            SELECT * FROM ag_catalog.cypher('support_graph', $$
                MATCH (n:{node_label})
                RETURN n.source_id as source_id, properties(n) as properties
            $$) AS (source_id agtype, properties agtype)
            LIMIT {limit}
        """)
        all_nodes = cur.fetchall()

        # Check which ones already have embeddings
        for node in all_nodes:
            source_id = str(node['source_id']).strip('"')
            cur.execute("""
                SELECT 1 FROM graphrag.node_embeddings
                WHERE node_label = %s AND source_id = %s AND embedding_type = %s
            """, (node_label, source_id, embedding_type))

            if cur.fetchone() is None:
                # Parse properties from agtype
                props = node['properties']
                if isinstance(props, str):
                    import json
                    props = json.loads(props) if props else {}

                nodes.append({
                    'node_label': node_label,
                    'source_id': source_id,
                    'properties': props
                })

    return nodes


def store_node_embedding(
    conn,
    node_label: str,
    source_id: str,
    embedding_type: str,
    embedding: List[float],
    embedded_text: str,
    model_name: str,
):
    """Store an embedding in the database."""
    with conn.cursor() as cur:
        embedding_str = format_embedding_for_postgres(embedding)
        cur.execute(
            "SELECT graphrag.store_node_embedding(%s, %s, %s, %s::vector, %s, %s)",
            (node_label, source_id, embedding_type, embedding_str, embedded_text, model_name),
        )
    conn.commit()


def process_nodes(
    node_label: str,
    embedding_type: str = "base",
    limit: int = 100,
    batch_size: int = 10,
    connection_string: Optional[str] = None,
    dry_run: bool = False,
):
    """
    Process graph nodes and generate embeddings.

    Args:
        node_label: Type of nodes to process (Ticket, Customer, etc.)
        embedding_type: Type of embedding ('base' or 'neighborhood')
        limit: Maximum number of nodes to process
        batch_size: Number of nodes to embed in one API call
        connection_string: PostgreSQL connection string
        dry_run: If True, don't actually store embeddings
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
        # Ensure AGE is loaded
        ensure_age_loaded(conn)

        # Fetch nodes needing embeddings
        print(f"Fetching {node_label} nodes needing '{embedding_type}' embeddings...")
        nodes = fetch_nodes_for_embedding(conn, node_label, embedding_type, limit)

        if not nodes:
            print("No nodes found needing embeddings.")
            return

        print(f"Found {len(nodes)} nodes to process.")

        # Build texts for embedding
        texts_to_embed = []
        for node in nodes:
            base_text = get_node_text(node['node_label'], node['properties'])

            if embedding_type == "neighborhood":
                # Add neighborhood context
                neighborhood = get_neighborhood_context(
                    conn, node['node_label'], node['source_id']
                )
                full_text = f"{base_text}\n\nRelationships:\n{neighborhood}" if neighborhood else base_text
            else:
                full_text = base_text

            node['text'] = full_text
            texts_to_embed.append(full_text)

        if dry_run:
            print("\n[DRY RUN] Would process these nodes:")
            for node in nodes[:5]:
                print(f"  - {node['node_label']}/{node['source_id']}")
                print(f"    Text: {node['text'][:100]}...")
            if len(nodes) > 5:
                print(f"  ... and {len(nodes) - 5} more")
            return

        # Process in batches
        processed = 0
        errors = 0

        with tqdm(total=len(nodes), desc=f"Generating {embedding_type} embeddings") as pbar:
            for i in range(0, len(nodes), batch_size):
                batch_nodes = nodes[i : i + batch_size]
                batch_texts = texts_to_embed[i : i + batch_size]

                try:
                    # Generate embeddings for batch
                    embeddings = generator.generate_batch(batch_texts, batch_size=batch_size)

                    # Store each embedding
                    for node, embedding, text in zip(batch_nodes, embeddings, batch_texts):
                        store_node_embedding(
                            conn,
                            node['node_label'],
                            node['source_id'],
                            embedding_type,
                            embedding,
                            text,
                            generator.model,
                        )
                        processed += 1
                        pbar.update(1)

                except Exception as e:
                    print(f"\nError processing batch: {e}")
                    errors += len(batch_nodes)
                    pbar.update(len(batch_nodes))

        print(f"\nCompleted: {processed} embeddings generated, {errors} errors.")

    finally:
        conn.close()


def process_all_node_types(
    embedding_type: str = "base",
    limit_per_type: int = 100,
    batch_size: int = 10,
    connection_string: Optional[str] = None,
    dry_run: bool = False,
):
    """
    Process all node types in the graph.

    Args:
        embedding_type: Type of embedding ('base' or 'neighborhood')
        limit_per_type: Maximum nodes per type to process
        batch_size: Batch size for API calls
        connection_string: PostgreSQL connection string
        dry_run: If True, don't actually store embeddings
    """
    node_types = ["Ticket", "Customer", "Product", "Agent", "KBArticle", "TicketMessage"]

    for node_type in node_types:
        print(f"\n{'='*60}")
        print(f"Processing {node_type} nodes...")
        print(f"{'='*60}")
        process_nodes(
            node_label=node_type,
            embedding_type=embedding_type,
            limit=limit_per_type,
            batch_size=batch_size,
            connection_string=connection_string,
            dry_run=dry_run,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Generate embeddings for GraphRAG nodes"
    )
    parser.add_argument(
        "--node-label",
        type=str,
        default=None,
        help="Node label to process (Ticket, Customer, etc.). If not specified, processes all types.",
    )
    parser.add_argument(
        "--embedding-type",
        choices=["base", "neighborhood"],
        default="base",
        help="Type of embedding to generate (default: base)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Maximum number of nodes to process per type (default: 100)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=10,
        help="Number of nodes per API call (default: 10)",
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

    if args.node_label:
        process_nodes(
            node_label=args.node_label,
            embedding_type=args.embedding_type,
            limit=args.limit,
            batch_size=args.batch_size,
            connection_string=args.database_url,
            dry_run=args.dry_run,
        )
    else:
        process_all_node_types(
            embedding_type=args.embedding_type,
            limit_per_type=args.limit,
            batch_size=args.batch_size,
            connection_string=args.database_url,
            dry_run=args.dry_run,
        )


if __name__ == "__main__":
    main()
