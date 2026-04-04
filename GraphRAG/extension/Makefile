# GraphRAG Extension Makefile
# Uses PGXS (PostgreSQL Extension Building Infrastructure)

EXTENSION = graphrag
DATA = graphrag--1.0.sql
PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Installation instructions:
# 1. Ensure Apache AGE and pgvector are installed
# 2. Run: make install
# 3. In PostgreSQL: CREATE EXTENSION graphrag;

.PHONY: install-deps
install-deps:
	@echo "Checking dependencies..."
	@psql -c "SELECT * FROM pg_extension WHERE extname = 'age';" || echo "AGE not installed"
	@psql -c "SELECT * FROM pg_extension WHERE extname = 'vector';" || echo "pgvector not installed"
