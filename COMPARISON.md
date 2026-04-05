# GraphRAG vs ContextRAG: Critical Comparative Analysis

## Executive Summary

This analysis critiques the architectural differences between GraphRAG (using Apache AGE property graphs) and ContextRAG (using flat entity-context tables with weights). Both systems solve the same problem—enriching vector similarity search with contextual information—but take fundamentally different approaches with distinct trade-offs.

---

## 1. Data Model Architecture

### ContextRAG: Three-Table Star Schema

```
┌─────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│    entities     │──1:N─│   entity_context    │      │  entity_embeddings  │
├─────────────────┤      ├─────────────────────┤      ├─────────────────────┤
│ id (UUID PK)    │      │ entity_id (FK)      │      │ entity_id (FK)      │
│ source_schema   │      │ context_type        │      │ embedding_type      │
│ source_table    │      │ context_key         │      │ embedding (1536)    │
│ source_id       │      │ context_value       │      │ model_name          │
│ entity_type     │      │ weight (0.0-1.0)    │      └─────────────────────┘
│ base_content    │      │ expires_at          │
│ metadata (JSONB)│      └─────────────────────┘
└─────────────────┘
```

**Strengths:**
- Simple, well-understood relational pattern
- Single source of truth (entities table)
- Flexible key-value context (any attribute can be added)
- Weight-based importance ordering
- Temporal context support (expires_at)

**Weaknesses:**
- No native relationship traversal
- Context is denormalized (e.g., "customer_name" stored as text, not FK)
- Relationships are implicit, not queryable
- No path-based reasoning possible

### GraphRAG: Property Graph + Vector Tables

```
┌─────────────────────────────────────────────────────────────────┐
│                    Apache AGE Graph                              │
│  ┌────────┐     CREATED_BY     ┌──────────┐                     │
│  │ Ticket │──────────────────►│ Customer │                     │
│  └────────┘                    └──────────┘                     │
│      │                              ▲                           │
│      │ ABOUT_PRODUCT               │ CREATED_BY                │
│      ▼                              │                           │
│  ┌─────────┐                   ┌────────┐                       │
│  │ Product │◄──DOCUMENTS──────│KBArticle│                       │
│  └─────────┘                   └────────┘                       │
└─────────────────────────────────────────────────────────────────┘
                              +
┌─────────────────────────────────────────────────────────────────┐
│                    Vector Tables (pgvector)                      │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │   node_embeddings   │    │   subgraph_cache    │             │
│  ├─────────────────────┤    ├─────────────────────┤             │
│  │ node_label          │    │ subgraph_text       │             │
│  │ source_id           │    │ max_hops, max_nodes │             │
│  │ embedding_type      │    │ is_valid            │             │
│  │ embedding (1536)    │    └─────────────────────┘             │
│  └─────────────────────┘                                        │
└─────────────────────────────────────────────────────────────────┘
```

**Strengths:**
- Explicit, typed relationships (CREATED_BY, ASSIGNED_TO, etc.)
- Native multi-hop traversal via Cypher
- Path-based reasoning and explanations
- Structural similarity (shared neighbors)
- Edge properties (e.g., similarity scores)

**Weaknesses:**
- More complex architecture (two systems: AGE + pgvector)
- Data duplication (relational + graph)
- No native weighting mechanism for relationships
- Requires synchronization between relational and graph data
- Cypher learning curve

---

## 2. Context Representation

### ContextRAG: Weighted Key-Value Attributes

```sql
-- Example: Ticket 1 context
('status', 'ticket_status', 'open', 0.3)
('priority', 'ticket_priority', 'urgent', 1.0)
('customer', 'customer_name', 'John Smith', 0.7)
('customer', 'plan_type', 'enterprise', 0.8)
('product', 'product_name', 'SecureAuth', 0.9)
('agent', 'assigned_agent', 'Tom Anderson', 0.5)
```

**Context Text Generation:**
```
priority: ticket_priority = urgent; customer: plan_type = enterprise;
product: product_name = SecureAuth; customer: customer_name = John Smith;
agent: assigned_agent = Tom Anderson; status: ticket_status = open
```

**Critique:**
- ✅ Weights provide explicit importance ranking
- ✅ Text ordering affects embedding quality (high-weight first)
- ❌ Relationships are flattened to strings (loses referential integrity)
- ❌ No way to traverse "find other tickets from same customer"
- ❌ Weight tuning is manual and domain-specific

### GraphRAG: Explicit Typed Relationships

```cypher
-- Example: Ticket 1 relationships
(Ticket:1)-[:CREATED_BY]->(Customer:1 {name: 'John Smith', plan: 'enterprise'})
(Ticket:1)-[:ASSIGNED_TO]->(Agent:1 {name: 'Tom Anderson', team: 'technical'})
(Ticket:1)-[:ABOUT_PRODUCT]->(Product:2 {name: 'SecureAuth'})
(Ticket:1)-[:REFERENCES]->(KBArticle:1 {title: 'SSO with Azure AD'})
```

**Graph Context Text Generation:**
```
Ticket: {"subject": "SSO not working", "status": "open", "priority": "urgent"}

Relationships:
  -[CREATED_BY]-> Customer (1)
  -[ASSIGNED_TO]-> Agent (1)
  -[ABOUT_PRODUCT]-> Product (2)
  -[REFERENCES]-> KBArticle (1)
```

**Critique:**
- ✅ Relationships are first-class citizens (can be queried, traversed)
- ✅ Referential integrity maintained (FK to actual entities)
- ✅ Multi-hop discovery possible ("Customer's other tickets")
- ❌ No built-in weighting (all edges are equal)
- ❌ Context text is structural, not weighted by importance
- ❌ Edge properties require manual population

---

## 3. Efficiency Analysis

### Storage Overhead

| Metric | ContextRAG | GraphRAG | Winner |
|--------|-----------|----------|--------|
| **Per-entity base storage** | ~500 bytes | ~500 bytes (node) | Tie |
| **Context/relationship storage** | ~100 bytes × 7 attrs = 700 bytes | ~50 bytes × 5 edges = 250 bytes | GraphRAG |
| **Embedding storage** | 6 KB × 2 types = 12 KB | 6 KB × 2 types = 12 KB | Tie |
| **Index overhead** | HNSW + B-tree + GIN | HNSW + B-tree + AGE graph indexes | ContextRAG (simpler) |
| **Total for 10K entities** | ~130 MB | ~150 MB (includes graph overhead) | ContextRAG |

**Analysis:**
- ContextRAG is ~15% more storage-efficient due to simpler architecture
- GraphRAG's AGE catalog tables add fixed overhead (~20 MB)
- Both scale linearly with entity count

### Query Complexity

| Operation | ContextRAG | GraphRAG |
|-----------|-----------|----------|
| **Simple vector search** | O(log N) HNSW | O(log N) HNSW |
| **Filtered search (metadata)** | O(F) GIN + O(log N) | O(V) Cypher + O(log N) |
| **Context-aware search** | O(C) context scan + O(log N) | O(degree) graph traverse + O(log N) |
| **Multi-hop discovery** | ❌ Not supported | O(degree^k) for k hops |
| **Structural similarity** | ❌ Not supported | O(degree²) neighbor intersection |

**Analysis:**
- For simple searches, both are equivalent
- ContextRAG has simpler query plans (pure SQL)
- GraphRAG's Cypher adds query planning overhead but enables new capabilities
- GraphRAG's multi-hop queries can be expensive (exponential in hop count)

### Write Performance

| Operation | ContextRAG | GraphRAG |
|-----------|-----------|----------|
| **Entity creation** | 1 INSERT | 1 Cypher CREATE + 1 INSERT (embeddings) |
| **Context/edge addition** | 1 INSERT | 1 Cypher MERGE per edge |
| **Embedding update** | 1 UPSERT | 1 UPSERT |
| **Full entity update** | 1 UPDATE + N context upserts | 1 Cypher SET + M edge updates |

**Analysis:**
- ContextRAG has simpler write path (pure SQL)
- GraphRAG requires Cypher for graph mutations (different driver/connection)
- GraphRAG edge updates are more granular (can update single relationship)
- ContextRAG context updates use UPSERT (cleaner)

---

## 4. Performance Comparison

### Benchmark Estimates (10K entities, 1536-dim embeddings)

| Query Type | ContextRAG | GraphRAG | Difference |
|------------|-----------|----------|------------|
| vector_search (5 results) | 5-10 ms | 5-10 ms | Tie |
| hybrid_search (metadata filter) | 10-20 ms | 15-30 ms | ContextRAG +33% faster |
| context_aware_search | 15-30 ms | N/A (use graph functions) | N/A |
| graph_enhanced_search | N/A | 20-40 ms | N/A |
| get_node_neighborhood | N/A | <1 ms | N/A |
| get_extended_context (2-hop) | N/A | 10-25 ms | N/A |
| multi_embedding_search | 15-30 ms | N/A | N/A |
| path_similarity_search | N/A | 25-50 ms | N/A |
| extract_subgraph_for_llm | N/A | 20-50 ms (cached: <1 ms) | N/A |

**Key Insights:**
1. **Pure vector search**: Identical performance (both use pgvector HNSW)
2. **Filtered search**: ContextRAG is faster (GIN index vs Cypher scan)
3. **Graph operations**: Only GraphRAG can do them (trade-off: capability vs speed)
4. **Caching**: GraphRAG's subgraph_cache amortizes expensive traversals

### Scaling Characteristics

| Scale | ContextRAG | GraphRAG |
|-------|-----------|----------|
| **1K entities** | <5 ms all queries | <10 ms all queries |
| **10K entities** | 5-30 ms | 10-50 ms |
| **100K entities** | 20-100 ms | 50-200 ms |
| **1M entities** | 100-500 ms | 200-1000 ms (graph traversals expensive) |

**Analysis:**
- ContextRAG scales more predictably (relational queries)
- GraphRAG's graph traversals become bottleneck at scale
- Both benefit from HNSW index for vector operations
- GraphRAG requires careful LIMIT clauses to avoid exponential blowup

---

## 5. Functional Differences

### Capabilities Matrix

| Capability | ContextRAG | GraphRAG |
|-----------|-----------|----------|
| Semantic similarity search | ✅ | ✅ |
| Metadata filtering | ✅ (JSONB @>) | ✅ (Cypher WHERE) |
| Weighted context in embeddings | ✅ (local_context type) | ⚠️ (neighborhood type, no weights) |
| Context attribute filtering | ✅ (context_aware_search) | ❌ (must use Cypher) |
| Multi-embedding blending | ✅ (multi_embedding_search) | ❌ Not implemented |
| 1-hop neighbor discovery | ❌ | ✅ (get_node_neighborhood) |
| Multi-hop traversal | ❌ | ✅ (get_extended_context) |
| Structural similarity | ❌ | ✅ (find_structurally_similar) |
| Path-based explanations | ❌ | ✅ (path_similarity_search) |
| Subgraph extraction for LLM | ❌ | ✅ (extract_subgraph_for_llm) |
| Temporal context expiration | ✅ (expires_at) | ❌ |
| Context weight tuning | ✅ (weight column) | ❌ |

### Where ContextRAG Excels

1. **Weighted Context Importance**
   ```sql
   -- ContextRAG can prioritize "urgent priority" over "assigned agent"
   SELECT build_context_text(entity_id)  -- Ordered by weight DESC
   -- Output: "priority: urgent; product: SecureAuth; customer: John; agent: Tom"
   ```
   GraphRAG treats all relationships equally—no way to say "CREATED_BY is more important than HAS_MESSAGE"

2. **Dual Embedding Strategy with Blending**
   ```sql
   -- ContextRAG blends base and context embeddings
   SELECT * FROM multi_embedding_search(query, 0.7, 0.3, 10)
   -- 70% weight on content, 30% weight on context
   ```
   GraphRAG has no equivalent—must choose base OR neighborhood

3. **Simpler Query Patterns**
   ```sql
   -- ContextRAG: Pure SQL, single roundtrip
   SELECT * FROM context_aware_search(emb, 'base', 10, 'ticket', 'priority', 'ticket_priority', 'urgent')

   -- GraphRAG: Requires Cypher + SQL combination
   WITH filtered AS (
       SELECT * FROM cypher('support_graph', $$ MATCH (t:Ticket {priority: 'urgent'}) RETURN t.source_id $$)
   )
   SELECT * FROM vector_search(...) WHERE source_id IN (SELECT * FROM filtered)
   ```

4. **Temporal Context**
   ```sql
   -- ContextRAG: Context can expire automatically
   INSERT INTO entity_context (..., expires_at) VALUES (..., NOW() + INTERVAL '7 days')
   -- Automatically excluded after expiration via WHERE expires_at > NOW()
   ```
   GraphRAG has no built-in edge expiration

### Where GraphRAG Excels

1. **Multi-Hop Discovery**
   ```cypher
   -- Find KB articles that helped resolve similar tickets from same customer
   MATCH (t:Ticket {source_id: '1'})-[:CREATED_BY]->(c:Customer)
         <-[:CREATED_BY]-(t2:Ticket {status: 'resolved'})
         -[:REFERENCES]->(kb:KBArticle)
   RETURN DISTINCT kb.title, t2.subject
   ```
   ContextRAG cannot do this—context attributes don't link to other entities

2. **Structural Similarity**
   ```sql
   -- Find tickets that share customer, product, AND agent
   SELECT * FROM find_structurally_similar('Ticket', '1', 'Ticket', 2, 5)
   -- Returns tickets with 2+ shared neighbors
   ```
   ContextRAG would require complex application logic to compare context values

3. **Path-Based Explanations**
   ```sql
   -- Explain WHY a KB article is relevant
   SELECT * FROM path_similarity_search(query_emb, 'KBArticle', 'Ticket', '1', 5)
   -- Returns: "Directly connected - highly relevant" or "Connected via shared entity"
   ```
   ContextRAG can only say "similarity score: 0.85"—no path provenance

4. **Rich LLM Context**
   ```sql
   -- Extract full subgraph for LLM prompt
   SELECT extract_subgraph_for_llm('Ticket', '1', 2, 20)
   ```
   Output includes:
   - Primary entity with all properties
   - 1-hop neighbors with relationship types
   - 2-hop neighbors with path descriptions

   ContextRAG's `build_full_text()` only includes flat key-value context

5. **Agent Expertise Discovery**
   ```cypher
   -- Find agent with most experience on SecureAuth resolved tickets
   MATCH (t:Ticket {status: 'resolved'})-[:ASSIGNED_TO]->(a:Agent),
         (t)-[:ABOUT_PRODUCT]->(p:Product {name: 'SecureAuth'})
   RETURN a.name, COUNT(t) as expertise_score
   ORDER BY expertise_score DESC LIMIT 1
   ```
   ContextRAG would require separate queries and application joins

---

## 6. Critical Architecture Trade-offs

### Trade-off 1: Simplicity vs Capability

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| Learning curve | Low (SQL only) | Medium (SQL + Cypher) |
| Debugging | Standard EXPLAIN ANALYZE | Cypher query plans are opaque |
| Extension development | Straightforward | Requires AGE expertise |
| Capability ceiling | Limited to flat context | Multi-hop, paths, structure |

**Verdict**: ContextRAG for teams without graph experience; GraphRAG when relationships are core to the domain

### Trade-off 2: Write Simplicity vs Query Power

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| Data ingestion | Single SQL transaction | SQL + Cypher mutations |
| Schema changes | ALTER TABLE | ALTER TABLE + graph schema |
| Sync complexity | None (single source) | Must sync relational ↔ graph |
| Query expressiveness | Limited | Rich (Cypher pattern matching) |

**Verdict**: ContextRAG for high-write workloads; GraphRAG for complex read patterns

### Trade-off 3: Determinism vs Flexibility

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| Context ordering | Deterministic (by weight) | Order depends on traversal |
| Embedding consistency | Weights ensure reproducibility | Neighborhood varies with graph changes |
| Query results | Predictable | Can change as edges are added |

**Verdict**: ContextRAG for regulated environments; GraphRAG for exploratory analytics

### Trade-off 4: Performance vs Richness

| Aspect | ContextRAG | GraphRAG |
|--------|-----------|----------|
| Simple queries | Faster (pure SQL) | Slightly slower (Cypher overhead) |
| Complex analysis | Must use application code | Native in database |
| Caching strategy | N/A (queries are fast) | Required for multi-hop (subgraph_cache) |

**Verdict**: ContextRAG for latency-critical paths; GraphRAG for analytical queries

---

## 7. Recommendations

### Use ContextRAG When:

1. **Relationships are flat**: Customer metadata, product attributes, status flags
2. **No multi-hop queries needed**: Each entity is independent
3. **Team lacks graph experience**: Faster development, easier maintenance
4. **Write-heavy workload**: Simpler ingestion pipeline
5. **Weighted importance matters**: Domain experts can tune context weights
6. **Temporal context**: Need automatic expiration of context attributes

### Use GraphRAG When:

1. **Rich relationships exist**: Customer → Tickets → KB Articles → Products
2. **Discovery is important**: "Find related entities I didn't know about"
3. **Explainability required**: "Why is this article relevant?"
4. **Structural patterns matter**: "Find tickets from customers with similar issues"
5. **Agent/expert routing**: "Who has experience with this product?"
6. **Customer journey analysis**: "What's the full context of this customer's history?"

### Use Both When:

1. **Hybrid workloads**: ContextRAG for fast simple searches, GraphRAG for deep analysis
2. **Gradual migration**: Start with ContextRAG, add GraphRAG for specific use cases
3. **A/B testing**: Compare retrieval quality between approaches
4. **Fallback strategy**: GraphRAG for primary, ContextRAG when graph is slow

---

## 8. Missing Features Analysis

### ContextRAG Could Benefit From:

1. **Relationship inference**: Auto-create context from FK relationships
2. **Context clustering**: Group related attributes for better embeddings
3. **Weight learning**: ML-based weight optimization from user feedback
4. **Context inheritance**: Child entities inherit parent context

### GraphRAG Could Benefit From:

1. **Edge weighting**: Allow relationship importance scores
2. **Multi-embedding blending**: Combine base + neighborhood with weights
3. **Temporal edges**: Built-in edge expiration like ContextRAG's expires_at
4. **Incremental sync**: Triggers to auto-update graph from relational changes
5. **Path caching**: Cache frequently-used path patterns (not just subgraphs)

---

## Conclusion

**ContextRAG** is the right choice for most RAG applications—it's simpler, faster for common queries, and provides sufficient context enrichment through weighted attributes. The dual-embedding strategy (base + local_context) effectively captures both content and context signals.

**GraphRAG** is superior when relationships are first-class concerns—when you need to traverse connections, explain paths, or discover structural patterns. The overhead of maintaining a property graph is justified when multi-hop queries provide genuine business value.

The two approaches are complementary, not competing. A production system might use ContextRAG for the 90% of queries that are simple semantic searches, and GraphRAG for the 10% that require relationship reasoning.
