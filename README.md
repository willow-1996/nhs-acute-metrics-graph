# Acute Metrics R Graph

Shiny + r2d3 port of the Acute Metrics Graph. Two deployment modes from the same code:

- **Server-backed** — run locally or on Shiny Server / shinyapps.io
- **Static / GitHub Pages** — export via shinylive (WebR in browser)

## Tabs

| Tab | What it does |
|-----|-------------|
| Graph | D3 force-directed graph, filtered by Shiny inputs |
| Metrics | Filterable DT table of all metric source CSVs |

## Run locally

```r
# Install dependencies (once)
install.packages(c("shiny", "r2d3", "readr", "dplyr", "purrr", "DT"))

# Run
shiny::runApp(".")
```

## Export as static app (shinylive / GitHub Pages)

```r
install.packages("shinylive")
shinylive::export(appdir = ".", destdir = "docs")
# Commit docs/ and enable GitHub Pages from /docs on main
```

## Data

| Path | Contents |
|------|----------|
| `data/nodes.csv` | Graph nodes |
| `data/edges.csv` | Graph edges |
| `data/nhs_oversight_metrics.csv` | NOF metric metadata |
| `data/metric-sources/*.csv` | Individual metric set source files |

Add new metric sets by dropping a CSV into `data/metric-sources/` following the shared schema
(`id, label, source_set, parent_domain, subdomain, specialty, metric_type, unit, direction, ...`).

## Architecture note

Graph filtering is done in R (server-side). When Shiny inputs change, `filter_graph()` runs,
filtered data is passed to r2d3, and the D3 force simulation re-runs with the new node/edge set.
The D3 code in `www/graph.js` is purely a renderer — no internal filter logic.

Node clicks in D3 send `clicked_node` to Shiny via `Shiny.setInputValue`, and Shiny renders
the detail panel in the sidebar.
