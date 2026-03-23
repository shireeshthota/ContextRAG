#!/bin/bash
# ContextRAG Installation Script
# This script installs the ContextRAG PostgreSQL extension

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}ContextRAG Installation Script${NC}"
echo "================================"

# Check for PostgreSQL
if ! command -v psql &> /dev/null; then
    echo -e "${RED}Error: PostgreSQL client (psql) not found${NC}"
    echo "Please install PostgreSQL first."
    exit 1
fi

# Check for pg_config (needed for extension installation)
if ! command -v pg_config &> /dev/null; then
    echo -e "${RED}Error: pg_config not found${NC}"
    echo "Please install PostgreSQL development headers."
    exit 1
fi

# Get database connection info
DB_NAME=${1:-contextrag_test}
DB_HOST=${PGHOST:-localhost}
DB_USER=${PGUSER:-$USER}

echo ""
echo "Target database: $DB_NAME"
echo "Host: $DB_HOST"
echo "User: $DB_USER"
echo ""

# Check if database exists
if ! psql -h "$DB_HOST" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${YELLOW}Database '$DB_NAME' does not exist. Creating...${NC}"
    createdb -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"
fi

# Check for pgvector
echo "Checking for pgvector extension..."
if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM pg_available_extensions WHERE name = 'vector';" | grep -q "1"; then
    echo -e "${RED}Error: pgvector extension not available${NC}"
    echo "Please install pgvector first: https://github.com/pgvector/pgvector"
    exit 1
fi

echo -e "${GREEN}pgvector is available${NC}"

# Install pgvector if not already installed
echo "Installing pgvector extension..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Determine installation method
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"

echo ""
echo "Choose installation method:"
echo "  1) Install as PostgreSQL extension (requires make & superuser)"
echo "  2) Run SQL migrations (no special permissions needed)"
read -p "Enter choice [1/2]: " choice

case $choice in
    1)
        echo ""
        echo "Installing PostgreSQL extension..."
        cd "$PROJECT_DIR/extension"

        if [ -f "Makefile" ]; then
            make
            sudo make install
            psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION contextrag;"
            echo -e "${GREEN}Extension installed successfully!${NC}"
        else
            echo -e "${RED}Error: Makefile not found in extension directory${NC}"
            exit 1
        fi
        ;;
    2)
        echo ""
        echo "Running SQL migrations..."
        cd "$PROJECT_DIR"

        echo "Running 001_create_core_tables.sql..."
        psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f migrations/001_create_core_tables.sql

        echo "Running 002_create_indexes.sql..."
        psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f migrations/002_create_indexes.sql

        echo "Running 003_create_functions.sql..."
        psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f migrations/003_create_functions.sql

        echo -e "${GREEN}Migrations applied successfully!${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Verify installation
echo ""
echo "Verifying installation..."
STATS=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM contextrag.get_stats();")

if [ "$STATS" -gt 0 ]; then
    echo -e "${GREEN}ContextRAG installed successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Set up Python environment: cd python && pip install -r requirements.txt"
    echo "  2. Set OPENAI_API_KEY environment variable"
    echo "  3. Run test project: cd test_project && see README.md"
else
    echo -e "${RED}Installation verification failed${NC}"
    exit 1
fi
