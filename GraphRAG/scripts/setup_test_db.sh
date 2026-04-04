#!/bin/bash
# =============================================================================
# GraphRAG Test Database Setup Script
# =============================================================================
# This script creates a test database with the GraphRAG extension and
# populates it with the CRM sample data.
#
# Usage: ./setup_test_db.sh [database_name]
# Default database: graphrag_test
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
DB_NAME="${1:-graphrag_test}"

echo "=== GraphRAG Test Database Setup ==="
echo "Database: $DB_NAME"
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "ERROR: psql not found. Please install PostgreSQL client."
    exit 1
fi

# Check if database exists and ask to drop
DB_EXISTS=$(psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';" postgres 2>/dev/null || echo "0")
if [ "$DB_EXISTS" = "1" ]; then
    read -p "Database '$DB_NAME' exists. Drop and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Dropping database '$DB_NAME'..."
        psql -c "DROP DATABASE IF EXISTS $DB_NAME;" postgres
    else
        echo "Aborted."
        exit 1
    fi
fi

# Create database
echo "Creating database '$DB_NAME'..."
psql -c "CREATE DATABASE $DB_NAME;" postgres

# Install extensions
echo "Installing extensions..."
psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS age;"
psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Run migrations
echo ""
echo "Running migrations..."
for migration in "$PROJECT_DIR"/migrations/*.sql; do
    echo "  Running: $(basename "$migration")"
    psql -d "$DB_NAME" -f "$migration" > /dev/null
done

# Create support schema and load seed data
echo ""
echo "Creating support schema..."
psql -d "$DB_NAME" -f "$PROJECT_DIR/test_project/schema/support_tickets.sql" > /dev/null

echo "Loading seed data..."
psql -d "$DB_NAME" -f "$PROJECT_DIR/test_project/data/seed_data.sql" > /dev/null

# Populate graph
echo "Populating graph..."
psql -d "$DB_NAME" -f "$PROJECT_DIR/test_project/data/create_graph.sql"

# Analyze tables
echo ""
echo "Analyzing tables..."
psql -d "$DB_NAME" -c "ANALYZE;" > /dev/null

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Database '$DB_NAME' is ready!"
echo ""
echo "Connection string:"
echo "  postgresql://localhost/$DB_NAME"
echo ""
echo "Next steps:"
echo ""
echo "1. Generate embeddings:"
echo "   cd python"
echo "   pip install -r requirements.txt"
echo "   export OPENAI_API_KEY=sk-..."
echo "   export DATABASE_URL=postgresql://localhost/$DB_NAME"
echo "   python graph_embed.py --embedding-type base"
echo ""
echo "2. Run example queries:"
echo "   psql -d $DB_NAME -f test_project/queries/cypher_examples.sql"
echo ""
echo "3. Run comparison tests:"
echo "   psql -d $DB_NAME -f test_project/queries/comparison_tests.sql"
echo ""
