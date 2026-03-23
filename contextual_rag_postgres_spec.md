# Functional Specification: Contextual Row-based RAG in Postgres

## 1. Overview

This document describes a system to enhance Retrieval-Augmented
Generation (RAG) for structured databases by introducing contextual
awareness at the row level within PostgreSQL. The system treats context
as a first-class construct, enabling more accurate, explainable, and
controllable retrieval compared to traditional RAG approaches.

## 2. Core Concept

Each database row is enriched with optional contextual layers: - Base
Record: Raw structured data - Local Context: Direct metadata about the
row - Propagated Context: Context inherited via relationships

This allows retrieval to consider both the row and its surrounding
semantic environment.

## 3. Objectives

-   Improve retrieval precision for structured data
-   Enable explainable retrieval through context and paths
-   Maintain compatibility with SQL filtering and constraints
-   Support incremental updates and freshness
-   Provide controllable context propagation

## 4. System Components

Tables: - entities: canonical rows - entity_context: local context
attributes - entity_edges: relationships between entities -
entity_embeddings: multiple embeddings per entity - context_paths:
optional materialized paths - retrieval_trace: logs retrieval reasoning

## 5. Embedding Strategy

Each entity may have multiple embeddings: - Base embedding (row
content) - Local context embedding - Optional propagated context
embedding

This avoids mixing heterogeneous semantics into a single vector.

## 6. Indexing Strategy

Use pgvector with HNSW indexes: - Separate indexes per embedding type -
Support top-k semantic search - Combine with SQL filtering for hybrid
retrieval

## 7. Retrieval Flow

1.  Parse query intent
2.  Apply SQL filtering
3.  Perform vector search (multi-embedding)
4.  Expand neighborhood via edges
5.  Rerank results
6.  Return results with provenance

## 8. Context Propagation Rules

-   Typed edges with semantics
-   Depth-limited traversal (typically 1-2)
-   Decay by hop count and time
-   Maintain provenance for all propagated data

## 9. Scoring Model

Final score combines: - Base similarity - Context similarity - Path
support - Recency - Authority - Penalties for long paths

## 10. Advantages

-   Higher retrieval precision
-   Better grounding and explainability
-   Native integration with SQL
-   Incremental updates
-   More controllable than GraphRAG

## 11. Limitations

-   Context explosion risk
-   Complexity in propagation tuning
-   Maintenance overhead
-   Need for careful schema design

## 12. Phased Implementation

Phase 1: Base + local context embeddings\
Phase 2: Add edge-based traversal\
Phase 3: Add propagated summaries

Each phase validates incremental value.

## 13. Use Cases

-   Customer support systems
-   Incident management
-   Sales and CRM data
-   Telemetry and monitoring
-   Enterprise data platforms

## 14. Conclusion

This approach bridges the gap between traditional RAG and GraphRAG,
providing a practical, scalable, and explainable retrieval mechanism for
structured databases within PostgreSQL.
