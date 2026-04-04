#!/bin/bash
# =============================================================================
# GraphRAG Extension Installation Script
# =============================================================================
# This script installs the GraphRAG extension into PostgreSQL.
#
# Prerequisites:
# - PostgreSQL 14+ with development headers
# - Apache AGE extension installed
# - pgvector extension installed
# - pg_config in PATH
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$SCRIPT_DIR/../extension"

echo "=== GraphRAG Extension Installation ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check pg_config
if ! command -v pg_config &> /dev/null; then
    echo "ERROR: pg_config not found. Please install PostgreSQL development headers."
    exit 1
fi

PG_VERSION=$(pg_config --version | grep -oE '[0-9]+' | head -1)
echo "PostgreSQL version: $PG_VERSION"

if [ "$PG_VERSION" -lt 14 ]; then
    echo "ERROR: PostgreSQL 14+ required. Found version $PG_VERSION."
    exit 1
fi

# Check for AGE extension
echo "Checking for Apache AGE extension..."
AGE_CHECK=$(psql -tAc "SELECT 1 FROM pg_available_extensions WHERE name = 'age';" 2>/dev/null || echo "0")
if [ "$AGE_CHECK" != "1" ]; then
    echo "WARNING: Apache AGE extension not found in available extensions."
    echo "Please install AGE from: https://age.apache.org/"
    echo "Continuing anyway..."
fi

# Check for pgvector extension
echo "Checking for pgvector extension..."
VECTOR_CHECK=$(psql -tAc "SELECT 1 FROM pg_available_extensions WHERE name = 'vector';" 2>/dev/null || echo "0")
if [ "$VECTOR_CHECK" != "1" ]; then
    echo "WARNING: pgvector extension not found in available extensions."
    echo "Please install pgvector from: https://github.com/pgvector/pgvector"
    echo "Continuing anyway..."
fi

# Install extension files
echo ""
echo "Installing extension files..."

SHAREDIR=$(pg_config --sharedir)
EXTENSION_DEST="$SHAREDIR/extension"

if [ ! -d "$EXTENSION_DEST" ]; then
    echo "ERROR: Extension directory not found: $EXTENSION_DEST"
    exit 1
fi

# Copy extension files
echo "Copying graphrag.control to $EXTENSION_DEST/"
cp "$EXTENSION_DIR/graphrag.control" "$EXTENSION_DEST/"

echo "Copying graphrag--1.0.sql to $EXTENSION_DEST/"
cp "$EXTENSION_DIR/graphrag--1.0.sql" "$EXTENSION_DEST/"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To use GraphRAG in your database:"
echo "  1. Connect to your database: psql -d your_database"
echo "  2. Create the extension: CREATE EXTENSION graphrag;"
echo "  3. Load AGE: SELECT graphrag.ensure_age_loaded();"
echo "  4. Create your graph: SELECT create_graph('your_graph');"
echo ""
echo "For the test project, run:"
echo "  ./scripts/setup_test_db.sh"
echo ""
