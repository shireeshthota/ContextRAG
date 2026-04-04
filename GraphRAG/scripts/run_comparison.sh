#!/bin/bash
# =============================================================================
# GraphRAG vs ContextRAG Comparison Script
# =============================================================================
# This script runs both GraphRAG and ContextRAG systems side-by-side
# with the same test queries to demonstrate their differences.
#
# Prerequisites:
# - GraphRAG test database set up (./setup_test_db.sh)
# - ContextRAG test database set up (from parent project)
# - Embeddings generated for both systems
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPHRAG_DIR="$SCRIPT_DIR/.."
CONTEXTRAG_DIR="$SCRIPT_DIR/../../"

GRAPHRAG_DB="${GRAPHRAG_DB:-graphrag_test}"
CONTEXTRAG_DB="${CONTEXTRAG_DB:-contextrag_test}"

echo "=== GraphRAG vs ContextRAG Comparison ==="
echo ""
echo "GraphRAG Database: $GRAPHRAG_DB"
echo "ContextRAG Database: $CONTEXTRAG_DB"
echo ""

# Check databases exist
for db in "$GRAPHRAG_DB" "$CONTEXTRAG_DB"; do
    DB_EXISTS=$(psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$db';" postgres 2>/dev/null || echo "0")
    if [ "$DB_EXISTS" != "1" ]; then
        echo "ERROR: Database '$db' not found."
        echo "Please set up both databases first."
        exit 1
    fi
done

echo "=== Test 1: Basic Query - Graph Statistics ==="
echo ""

echo "--- GraphRAG Stats ---"
psql -d "$GRAPHRAG_DB" -c "
LOAD 'age';
SET search_path = ag_catalog, graphrag;
SELECT * FROM graphrag.get_graph_stats();
"

echo ""
echo "--- ContextRAG Stats ---"
psql -d "$CONTEXTRAG_DB" -c "
SELECT * FROM contextrag.get_stats();
"

echo ""
echo "=== Test 2: Neighborhood Context ==="
echo ""

echo "--- GraphRAG: Ticket 1 Neighborhood ---"
psql -d "$GRAPHRAG_DB" -c "
LOAD 'age';
SET search_path = ag_catalog, graphrag;
SELECT * FROM graphrag.get_node_neighborhood('Ticket', '1');
"

echo ""
echo "--- ContextRAG: Ticket 1 Context ---"
psql -d "$CONTEXTRAG_DB" -c "
SELECT context_type, context_key, context_value, weight
FROM contextrag.entity_context ec
JOIN contextrag.entities e ON ec.entity_id = e.id
WHERE e.source_table = 'tickets' AND e.source_id = '1'
ORDER BY weight DESC;
"

echo ""
echo "=== Test 3: Subgraph/Context for LLM ==="
echo ""

echo "--- GraphRAG: Subgraph Extraction ---"
psql -d "$GRAPHRAG_DB" -c "
LOAD 'age';
SET search_path = ag_catalog, graphrag;
SELECT graphrag.extract_subgraph_for_llm('Ticket', '1', 2, 10, FALSE);
"

echo ""
echo "--- ContextRAG: Full Text Context ---"
psql -d "$CONTEXTRAG_DB" -c "
SELECT contextrag.build_full_text(e.id)
FROM contextrag.entities e
WHERE e.source_table = 'tickets' AND e.source_id = '1';
"

echo ""
echo "=== Test 4: Structural Similarity (GraphRAG only) ==="
echo ""

echo "--- GraphRAG: Tickets sharing entities with Ticket 1 ---"
psql -d "$GRAPHRAG_DB" -c "
LOAD 'age';
SET search_path = ag_catalog, graphrag;
SELECT * FROM graphrag.find_structurally_similar('Ticket', '1', 'Ticket', 1, 5);
"

echo ""
echo "Note: ContextRAG does not have native structural similarity."
echo "It would require application-level logic to compare context attributes."

echo ""
echo "=== Test 5: Multi-hop Discovery (GraphRAG only) ==="
echo ""

echo "--- GraphRAG: Find KB articles via customer's other resolved tickets ---"
psql -d "$GRAPHRAG_DB" -c "
LOAD 'age';
SET search_path = ag_catalog, graphrag, support;

SELECT * FROM ag_catalog.cypher('support_graph', \$\$
    MATCH (t1:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)<-[:CREATED_BY]-(t2:Ticket)-[:REFERENCES]->(kb:KBArticle)
    WHERE t1 <> t2
    RETURN DISTINCT kb.title as article, t2.subject as via_ticket
\$\$) AS (article agtype, via_ticket agtype);
"

echo ""
echo "Note: ContextRAG cannot do multi-hop traversals natively."
echo ""

echo "=== Comparison Complete ==="
echo ""
echo "Key observations:"
echo "1. GraphRAG provides explicit relationship traversal"
echo "2. ContextRAG is simpler for flat attribute filtering"
echo "3. GraphRAG excels at multi-hop discovery"
echo "4. ContextRAG has lower query complexity for basic RAG"
echo ""
echo "Run the full comparison tests with:"
echo "  psql -d $GRAPHRAG_DB -f test_project/queries/comparison_tests.sql"
echo ""
