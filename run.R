.libPaths(c("~/R/library", .libPaths()))
library(shiny)
shiny::runApp(".", host = "100.112.210.121", port = 8766, launch.browser = FALSE)
