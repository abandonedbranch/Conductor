# Scientific Research Tools — Design Spec

## Overview

Add five scientific research tools to Conductor so the on-device FoundationModels agent can search and synthesize academic literature. Each tool searches a free, no-auth API, returns abstracts for the model to reason over, and registers tappable source links for the user.

## Architecture

### Approach: One File Per Tool

Each tool lives in its own Swift file under `Conductor/Tools/`. Shared types are extracted to `ToolSupport.swift`. ContentView stays focused on chat UI.

```
Conductor/
  Tools/
    ToolSupport.swift                  (BadgedTool, ToolBadge, ToolSource, ToolUsageTracker, BadgeTint)
    WikipediaSearchTool.swift          (extracted from ContentView)
    PubMedSearchTool.swift
    SemanticScholarSearchTool.swift
    ArXivSearchTool.swift
    OpenAlexSearchTool.swift
    CrossRefSearchTool.swift
  ContentView.swift                    (chat UI, session setup, registers all tools)
```

### Shared Types (`ToolSupport.swift`)

Extracted from ContentView without changes:

- `BadgeTint` — enum of codable color cases
- `ToolBadge` — icon, tint, label
- `ToolSource` — title, url (displayed as tappable citations)
- `ToolUsageTracker` — actor that records badges and sources per response
- `BadgedTool` — protocol extending `Tool` with a `badge` property

### Tool Contract

Every tool:

1. Conforms to `BadgedTool` (has `badge` and `tracker` properties)
2. Declares `@Generable Arguments` with a `searchQuery: String` and optional `maxResults: Int?`
3. In `call()`:
   - Records its badge via `tracker.record(badge)`
   - Calls the API
   - Registers a `ToolSource` for each result via `tracker.addSource(...)`
   - Returns a formatted string with titles + abstracts for the model to synthesize
   - Catches API errors and returns a descriptive string (never throws)
4. Defaults to 3 results to stay within the on-device context budget

## Tool Specifications

### 1. PubMedSearchTool

- **Badge:** red, `cross.case`, "PubMed"
- **API:** NCBI E-utilities (no auth, rate-limited to 3 req/sec without API key)
  - Step 1: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax={max}&term={query}`
  - Step 2: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id={pmid1},{pmid2},...`
- **Parsing:** Step 1 returns JSON with PMID list. Step 2 returns XML; parse `<ArticleTitle>`, `<AbstractText>`, `<PMID>` elements using Foundation's `XMLParser` (delegate-based, no external dependencies).
- **Source URL format:** `https://pubmed.ncbi.nlm.nih.gov/{PMID}`
- **Tool output format:**
  ```
  PubMed results for "{query}":

  1. {Title}
  Authors: {AuthorList}
  PMID: {pmid}
  Abstract: {abstract text, truncated to ~400 chars}

  2. ...

  Sources registered as tappable links.
  ```

### 2. SemanticScholarSearchTool

- **Badge:** blue, `brain.head.profile`, "Semantic Scholar"
- **API:** `https://api.semanticscholar.org/graph/v1/paper/search?query={query}&limit={max}&fields=title,abstract,authors,year,citationCount,url`
- **Parsing:** JSON. Top-level `data` array of paper objects.
- **Source URL format:** `url` field from response (e.g., `https://www.semanticscholar.org/paper/...`)
- **Tool output format:**
  ```
  Semantic Scholar results for "{query}":

  1. {Title} ({year})
  Authors: {author names}
  Citations: {count}
  Abstract: {abstract, truncated to ~400 chars}

  2. ...
  ```

### 3. ArXivSearchTool

- **Badge:** green, `doc.text`, "arXiv"
- **API:** `https://export.arxiv.org/api/query?search_query=all:{query}&max_results={max}`
- **Parsing:** Atom XML feed. Parse `<entry>` elements for `<title>`, `<summary>`, `<id>`, `<author><name>`.
- **Source URL format:** `<id>` element value (e.g., `https://arxiv.org/abs/2301.12345`)
- **Tool output format:**
  ```
  arXiv results for "{query}":

  1. {Title}
  Authors: {author names}
  Abstract: {summary, truncated to ~400 chars}

  2. ...
  ```

### 4. OpenAlexSearchTool

- **Badge:** purple, `books.vertical`, "OpenAlex"
- **API:** `https://api.openalex.org/works?search={query}&per_page={max}&select=id,doi,title,authorships,publication_year,cited_by_count,abstract_inverted_index`
- **Parsing:** JSON. The `results` array contains work objects. Abstract is stored as an inverted index — reconstruct by sorting word positions.
- **Source URL format:** `doi` field as `https://doi.org/{doi}`, falling back to the OpenAlex `id` URL
- **Tool output format:**
  ```
  OpenAlex results for "{query}":

  1. {Title} ({year})
  Authors: {author names}
  Citations: {cited_by_count}
  Abstract: {reconstructed abstract, truncated to ~400 chars}

  2. ...
  ```

### 5. CrossRefSearchTool

- **Badge:** gray, `link.circle`, "CrossRef"
- **API:** `https://api.crossref.org/works?query={query}&rows={max}&select=DOI,title,author,abstract,published-print,is-referenced-by-count`
- **Parsing:** JSON. `message.items` array. Abstract may contain HTML entities — strip tags.
- **Source URL format:** `https://doi.org/{DOI}`
- **Tool output format:**
  ```
  CrossRef results for "{query}":

  1. {Title} ({year})
  Authors: {author names}
  Citations: {is-referenced-by-count}
  Abstract: {abstract with HTML stripped, truncated to ~400 chars}

  2. ...
  ```

## Session Registration

In `ChatDetailView.init`, all tools are registered with the session:

```swift
let tools: [any Tool] = [
    WikipediaSearchTool(tracker: tracker),
    PubMedSearchTool(tracker: tracker),
    SemanticScholarSearchTool(tracker: tracker),
    ArXivSearchTool(tracker: tracker),
    OpenAlexSearchTool(tracker: tracker),
    CrossRefSearchTool(tracker: tracker),
]
```

## System Instructions Update

The instructions are updated to describe each tool's strength so the model picks appropriately:

- **WikipediaSearchTool** — general knowledge, overviews, historical context
- **PubMedSearchTool** — biomedical and clinical research papers
- **SemanticScholarSearchTool** — broad academic research across all disciplines
- **ArXivSearchTool** — cutting-edge preprints in physics, math, CS, biology
- **OpenAlexSearchTool** — broad coverage, citation data, cross-disciplinary search
- **CrossRefSearchTool** — DOI metadata, publisher information, citation counts

The model is instructed to:
- Use the most relevant tool for the domain (e.g., PubMed for medical topics)
- Combine multiple tools when appropriate (e.g., PubMed + arXiv for biomedical preprints)
- Always synthesize results into a coherent answer rather than dumping raw data
- Never apologize or refuse — search first, explain limitations if no results found

## Error Handling

All tools catch errors internally and return descriptive strings:
- Network failures: "Could not reach {service}. Check your internet connection."
- No results: "{Service} returned no results for '{query}'. Try a broader or different search term."
- Parse failures: "Failed to parse {service} response."

## Context Budget

Default 3 results per tool. Abstracts truncated to ~400 characters. This keeps a single tool call under ~1500 tokens, leaving room for the model's synthesis and conversation history.

## Privacy

All tools make network requests to public APIs. The system instructions already require transparency when using tools that access the internet. Each tool's badge and source links make it visible to the user which services were contacted.
