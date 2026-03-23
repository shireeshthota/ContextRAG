#!/bin/bash
# Setup Test Database for ContextRAG
# This script creates a test database and populates it with sample data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}ContextRAG Test Database Setup${NC}"
echo "================================="

# Get database connection info
DB_NAME=${1:-contextrag_test}
DB_HOST=${PGHOST:-localhost}
DB_USER=${PGUSER:-$USER}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"

echo ""
echo "Target database: $DB_NAME"
echo "Host: $DB_HOST"
echo "User: $DB_USER"
echo ""

# Check if database exists
if psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    echo -e "${YELLOW}Database '$DB_NAME' already exists.${NC}"
    read -p "Drop and recreate? [y/N]: " confirm
    if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
        echo "Dropping database..."
        dropdb -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"
    else
        echo "Continuing with existing database..."
    fi
fi

# Create database if it doesn't exist
if ! psql -h "$DB_HOST" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    echo "Creating database '$DB_NAME'..."
    createdb -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"
fi

# Install pgvector
echo ""
echo "Installing pgvector extension..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || {
    echo -e "${RED}Error: Could not install pgvector. Is it installed on your system?${NC}"
    echo "See: https://github.com/pgvector/pgvector#installation"
    exit 1
}

# Run ContextRAG migrations
echo ""
echo "Installing ContextRAG schema..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/migrations/001_create_core_tables.sql"
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/migrations/002_create_indexes.sql"
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/migrations/003_create_functions.sql"

# Create test project schema
echo ""
echo "Creating support ticket schema..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/test_project/schema/support_tickets.sql"

# Load seed data
echo ""
echo "Loading seed data..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/test_project/data/seed_data.sql"

# Register entities
echo ""
echo "Registering entities..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_DIR/test_project/data/register_entities.sql"

# Show stats
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Database statistics:"
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM contextrag.get_stats();"

echo ""
echo "Next steps:"
echo "  1. Set up Python environment:"
echo "     cd $PROJECT_DIR/python"
echo "     pip3 install -r requirements.txt"
echo ""
echo "  2. Set your OpenAI API key:"
echo "     export OPENAI_API_KEY=your_key_here"
echo ""
echo "  3. Generate embeddings:"
echo "     python3 batch_embed.py --embedding-type base"
echo "     python3 batch_embed.py --embedding-type local_context"
echo ""
echo "  4. Run example queries:"
echo "     psql -d $DB_NAME -f $PROJECT_DIR/test_project/queries/search_examples.sql"
