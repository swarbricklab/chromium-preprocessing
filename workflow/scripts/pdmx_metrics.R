#!/usr/bin/env Rscript
# Predemux Script 3: Gather impact of each filter on the captures for reporting

library(argparser)
suppressPackageStartupMessages({
  library(Seurat)
  library(SeuratObject)
  library(dplyr)
  library(readr) 
  library(tibble)
})

p <- arg_parser("Gather cumulative filter metrics for reporting")
p <- add_argument(p, "--input-rds", help="Path to the input Seurat object RDS file", type="character")
p <- add_argument(p, "--output-csv-genes", help="Path to save the genes-per-cell metrics CSV", type="character")
p <- add_argument(p, "--output-csv-mito", help="Path to save the mito-percentage metrics CSV", type="character")
p <- add_argument(p, "--output-csv-umi", help="Path to save the UMI-count metrics CSV", type="character")
p <- add_argument(p, "--capture-id", help="Capture ID for logging and reporting", type="character", default="unknown_capture")
p <- add_argument(p, "--log-file", help="Path to the log file", type="character", default=NULL)

arguments <- parse_args(p)

# --- Validation of input params ---
if (is.na(arguments$input_rds) || is.na(arguments$output_csv_genes) || is.na(arguments$output_csv_mito) || is.na(arguments$output_csv_umi)){
  print(p)
  stop("Input RDS (--input-rds) and all three output CSV paths (--output-csv-*) must be supplied.", call.=FALSE)
}

# --- Logging Setup ---
if (!is.null(arguments$log_file) && !is.na(arguments$log_file)) {
    log_con <- file(arguments$log_file, open="wt")
    sink(log_con, type="output")
    sink(log_con, type="message")
    on.exit({
        sink(type="output")
        sink(type="message")
        close(log_con)
    }, add = TRUE)
}

# --- Main Workflow ---
capture_id <- arguments$capture_id
input_rds <- arguments$input_rds
output_csv_genes <- arguments$output_csv_genes
output_csv_mito <- arguments$output_csv_mito
output_csv_umi <- arguments$output_csv_umi

message(sprintf("Starting filter metrics generation for capture: %s", capture_id))
message(sprintf("Input Seurat RDS: %s", input_rds))

tryCatch({
    # Load Seurat object
    message("Loading Seurat object...")
    seurat_object <- readRDS(input_rds)
    if (is.null(seurat_object)) {
        stop(paste("Failed to load Seurat object from:", input_rds), call.=FALSE)
    }
    total_cells <- ncol(seurat_object)
    message(sprintf("Loaded object with %d cells.", total_cells))

    if (total_cells == 0) {
        message("Input Seurat object has 0 cells. Writing empty metrics files.")
        # Create empty data frames with correct columns and write them
        empty_df <- tibble(threshold = numeric(), cumulative_prop_discarded = numeric(), capture_id = character())
        write_csv(empty_df, output_csv_genes)
        write_csv(empty_df, output_csv_mito)
        write_csv(empty_df, output_csv_umi)

    } else {
        # --- Calculate Metrics for Each Filter Independently ---

        # Check if necessary metadata exists (percent.mt calculated in Script 1)
        if (!("percent.mt" %in% colnames(seurat_object@meta.data))) {
           stop("Metadata column 'percent.mt' not found. Ensure Script 1 ran correctly and added it.", call.=FALSE)
        }
        if (!("nFeature_RNA" %in% colnames(seurat_object@meta.data))) {
           stop("Metadata column 'nFeature_RNA' not found.", call.=FALSE)
        }
         if (!("nCount_RNA" %in% colnames(seurat_object@meta.data))) {
           stop("Metadata column 'nCount_RNA' not found.", call.=FALSE)
        }

        # Define threshold ranges to evaluate
        gene_thresholds <- c(0, 50, 100, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000, 5000)
        # Mito: High threshold = less filtering.
        mito_thresholds <- c(100, 90, 80, 70, 60, 50, 40, 30, 25, 20, 15, 10, 5, 2.5, 1, 0)
        umi_thresholds <- c(0, 100, 250, 500, 750, 1000, 1500, 2000, 3000, 5000, 7500, 10000, 15000, 20000)

        # Function to calculate cumulative proportion discarded
        calculate_cumulative_discard <- function(metadata_vector, thresholds, filter_type) {
            results <- numeric(length(thresholds))
            # Handle potential NAs in metadata (e.g., percent.mt if counts were 0)
            # For filtering purposes, set NAs to 0
            metadata_vector[is.na(metadata_vector)] <- 0

            for (i in seq_along(thresholds)) {
                thresh <- thresholds[i]
                if (filter_type == "min") { # e.g., min_genes (discard if < thresh)
                    discarded_count <- sum(metadata_vector <= thresh, na.rm = TRUE)
                } else if (filter_type == "max") { # e.g., max_mito (discard if > thresh)
                    discarded_count <- sum(metadata_vector >= thresh, na.rm = TRUE)
                } else {
                   stop("Invalid filter_type specified.")
                }
                results[i] <- if (total_cells > 0) discarded_count / total_cells else 0.0
            }
            tibble(threshold = thresholds, cumulative_prop_discarded = results, capture_id = capture_id)
        }

        # 1. Minimum Genes per Cell
        message("Calculating metrics for minimum genes per cell...")
        gene_metrics <- calculate_cumulative_discard(seurat_object$nFeature_RNA, gene_thresholds, "min")
        write_csv(gene_metrics, output_csv_genes)
        message(sprintf("Saved gene metrics to: %s", output_csv_genes))

        # 2. Maximum Mitochondrial Percentage
        message("Calculating metrics for maximum mitochondrial percentage...")
        mito_metrics <- calculate_cumulative_discard(seurat_object$percent.mt, mito_thresholds, "max")
        write_csv(mito_metrics, output_csv_mito)
        message(sprintf("Saved mito metrics to: %s", output_csv_mito))

        # 3. Minimum UMI Count
        message("Calculating metrics for minimum UMI count...")
        umi_metrics <- calculate_cumulative_discard(seurat_object$nCount_RNA, umi_thresholds, "min")
        write_csv(umi_metrics, output_csv_umi)
        message(sprintf("Saved UMI metrics to: %s", output_csv_umi))
    } # End else block for total_cells > 0

}, error = function(e) {
    message(sprintf("Error during metrics generation for %s: %s", capture_id, e$message))
    stop(e$message, call.=FALSE)
})

message(sprintf("Successfully completed metrics generation for capture: %s", capture_id))