.libPaths(c("~/R/library", .libPaths()))

library(shiny)
library(r2d3)
library(readr)
library(dplyr)
library(purrr)
library(DT)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && nchar(a[1]) > 0) a else b

# Convert a data frame to a list of row-objects so jsonlite serialises it as a
# JSON array of objects (not column-oriented) when nested inside a list for r2d3
df_rows <- function(df) {
  if (nrow(df) == 0) return(list())
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, ]))
}

# ---- Load data at startup -----------------------------------------------

nodes <- read_csv("data/nodes.csv",                 show_col_types = FALSE)
edges <- read_csv("data/edges.csv",                 show_col_types = FALSE)
nof   <- read_csv("data/nhs_oversight_metrics.csv", show_col_types = FALSE)

nof_ids    <- nof$id
node_types <- sort(unique(nodes$type))

focus_opts <- c(
  "Whole graph" = "",
  setNames(nodes$id, paste0(nodes$label, " · ", nodes$type))
)

metric_files <- list.files("data/metric-sources", pattern = "\\.csv$", full.names = TRUE)

metrics_all <- if (length(metric_files) > 0) {
  map(metric_files, read_csv, show_col_types = FALSE, col_types = cols(.default = "c")) |>
    bind_rows() |>
    distinct(id, .keep_all = TRUE) |>
    arrange(parent_domain, subdomain, id)
} else {
  data.frame()
}

domain_opts <- if (nrow(metrics_all) > 0) {
  sort(unique(metrics_all$parent_domain[!is.na(metrics_all$parent_domain)]))
} else character(0)

source_opts <- if (nrow(metrics_all) > 0) {
  sort(unique(metrics_all$source_set[!is.na(metrics_all$source_set)]))
} else character(0)

# ---- Graph filter helper ------------------------------------------------

filter_graph <- function(search = "", focus = "", visible_types = node_types, nof_only = FALSE) {
  ids <- nodes$id

  if (nchar(focus) > 0) {
    ids <- unique(c(focus,
                    edges$target[edges$source == focus],
                    edges$source[edges$target == focus]))
  }

  if (nof_only) {
    nof_nbrs <- unique(c(nof_ids,
                         edges$target[edges$source %in% nof_ids],
                         edges$source[edges$target %in% nof_ids]))
    ids <- intersect(ids, nof_nbrs)
  }

  vis <- nodes |> filter(id %in% ids, type %in% visible_types)

  if (nchar(trimws(search)) > 0)
    vis <- vis |> filter(grepl(search, paste(id, label, type, description), ignore.case = TRUE))

  vis_ids   <- vis$id
  vis_edges <- edges |> filter(source %in% vis_ids, target %in% vis_ids)

  list(
    nodes  = df_rows(vis),
    edges  = df_rows(vis_edges),
    nof    = df_rows(nof),
    counts = list(
      nodes      = nrow(nodes),
      edges      = nrow(edges),
      nofMetrics = nrow(nof),
      badEdges   = 0L,
      visible    = list(nodes = nrow(vis), edges = nrow(vis_edges))
    )
  )
}

# ---- UI -----------------------------------------------------------------

ui <- fluidPage(
  tags$head(
    tags$link(rel = "stylesheet", href = "styles.css"),
    tags$title("Acute Metrics Graph")
  ),

  tags$header(class = "amg-header",
    tags$div(
      tags$p(class = "eyebrow", "NHS analytics · knowledge graph"),
      tags$h1("Acute Metrics Graph")
    )
  ),

  tabsetPanel(id = "tabs", type = "tabs",

    # ---- Graph tab ----
    tabPanel("Graph",
      div(class = "graph-tab",

        tags$aside(class = "graph-aside",
          div(class = "panel",
            tags$label("Search"),
            textInput("search", NULL, placeholder = "domain, metric, product…"),
            tags$label("Focus node"),
            selectInput("focus", NULL, choices = focus_opts, width = "100%"),
            div(class = "filter-heading",
              tags$label("Node types"),
              actionLink("show_all_types", "Show all")
            ),
            checkboxGroupInput("vis_types", NULL,
              choices  = setNames(node_types, node_types),
              selected = node_types
            ),
            checkboxInput("nof_only", "NOF-linked neighbourhood only", FALSE),
            actionButton("refresh", "↺  Refresh", class = "btn-refresh")
          ),
          div(class = "panel", uiOutput("stats_ui")),
          div(class = "panel", uiOutput("detail_ui"))
        ),

        div(class = "graph-main",
          d3Output("graph", width = "100%", height = "100%")
        )
      )
    ),

    # ---- Metrics tab ----
    tabPanel("Metrics",
      div(class = "metrics-tab",
        fluidRow(
          column(3, selectInput("m_domain",    "Parent domain",
            choices = c("All" = "", domain_opts))),
          column(3, selectInput("m_direction", "Direction",
            choices = c("All" = "", "higher_better", "lower_better", "target", "neutral"))),
          column(3, selectInput("m_source",    "Source set",
            choices = c("All" = "", source_opts))),
          column(3, textInput("m_search", "Search",
            placeholder = "label, specialty, subdomain…"))
        ),
        DTOutput("metrics_table")
      )
    )
  )
)

# ---- Server -------------------------------------------------------------

server <- function(input, output, session) {

  observeEvent(input$show_all_types, {
    updateCheckboxGroupInput(session, "vis_types", selected = node_types)
  })

  gdata <- reactive({
    input$refresh
    filter_graph(
      search        = input$search    %||% "",
      focus         = input$focus     %||% "",
      visible_types = input$vis_types %||% node_types,
      nof_only      = isTRUE(input$nof_only)
    )
  })

  output$graph <- renderD3({
    r2d3(data = gdata(), script = "www/graph.js", d3_version = 6)
  })

  output$stats_ui <- renderUI({
    d <- gdata()
    div(class = "stats-grid",
      div(class = "stat", tags$strong(d$counts$nodes),      span("Total nodes")),
      div(class = "stat", tags$strong(d$counts$edges),      span("Total edges")),
      div(class = "stat", tags$strong(d$counts$nofMetrics), span("NOF metrics")),
      div(class = "stat",
        tags$strong(paste0(d$counts$visible$nodes, " / ", d$counts$visible$edges)),
        span("Visible n / e"))
    )
  })

  # Node detail on click from D3
  clicked <- reactiveVal(NULL)

  observeEvent(input$clicked_node, {
    id <- input$clicked_node
    n  <- nodes[nodes$id == id, ]
    if (nrow(n) == 0) { clicked(NULL); return() }
    clicked(list(
      node  = n,
      out   = edges[edges$source == id, ],
      inb   = edges[edges$target == id, ],
      nof_r = nof[nof$id == id, ]
    ))
  })

  output$detail_ui <- renderUI({
    d <- clicked()
    if (is.null(d))
      return(p("Click a node to inspect it.", class = "muted"))
    n <- d$node
    tagList(
      div(class = "details-type", n$type),
      tags$h3(n$label, class = "details-title"),
      tags$code(n$id),
      p(n$description %||% "", class = "description"),
      if (nrow(d$nof_r) > 0) tagList(
        tags$h4("NOF"),
        tags$ul(
          tags$li(strong("Domain: "),    d$nof_r$nof_domain),
          tags$li(strong("Subdomain: "), d$nof_r$nof_subdomain),
          tags$li(strong("Status: "),    d$nof_r$scoring_status),
          tags$li(tags$a("Source ↗", href = d$nof_r$source_url, target = "_blank"))
        )
      ),
      tags$h4(paste0("Outgoing (", nrow(d$out), ")")),
      if (nrow(d$out) > 0)
        tags$ul(lapply(seq_len(min(15, nrow(d$out))), function(i)
          tags$li(strong(d$out$type[i]), " → ", tags$code(d$out$target[i]))))
      else p("None", class = "muted"),
      tags$h4(paste0("Incoming (", nrow(d$inb), ")")),
      if (nrow(d$inb) > 0)
        tags$ul(lapply(seq_len(min(15, nrow(d$inb))), function(i)
          tags$li(tags$code(d$inb$source[i]), " → ", strong(d$inb$type[i]))))
      else p("None", class = "muted")
    )
  })

  # Metrics table
  output$metrics_table <- renderDT({
    m <- metrics_all
    if (nrow(m) == 0)
      return(datatable(data.frame(message = "No metric source files found in data/metric-sources/")))

    if (nchar(input$m_domain    %||% "") > 0) m <- m[m$parent_domain == input$m_domain    & !is.na(m$parent_domain), ]
    if (nchar(input$m_direction %||% "") > 0) m <- m[m$direction     == input$m_direction & !is.na(m$direction), ]
    if (nchar(input$m_source    %||% "") > 0) m <- m[m$source_set    == input$m_source    & !is.na(m$source_set), ]
    if (nchar(trimws(input$m_search %||% "")) > 0) {
      q <- tolower(trimws(input$m_search))
      m <- m[grepl(q, tolower(paste(m$label, m$subdomain, m$specialty, sep = " ")), fixed = TRUE), ]
    }

    show <- c("id", "label", "source_set", "parent_domain", "subdomain",
              "specialty", "metric_type", "unit", "direction", "scoring_status")
    m <- m[, intersect(show, names(m)), drop = FALSE]

    datatable(m,
      rownames  = FALSE,
      filter    = "top",
      extensions = "Buttons",
      options   = list(
        pageLength = 25,
        scrollX    = TRUE,
        dom        = "Bfrtip",
        buttons    = c("csv", "excel")
      ),
      class = "stripe hover compact"
    )
  })
}

shinyApp(ui, server)
