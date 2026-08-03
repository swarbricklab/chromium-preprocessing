#!/usr/bin/env Rscript
# Predemux Script 2: Apply pre-set filters to Seurat object and save Cell Ranger outputs

library(argparser)
suppressPackageStartupMessages({
  library(Seurat)
  library(SeuratObject)
  library(DropletUtils)
  library(dplyr) 
  library(Matrix) 
})

arguments <- arg_parser("Apply filters to Seurat object and save outputs") %>%
  add_argument("--input-rds",
               help = "Path to the input Seurat object RDS file",
               type = "character",
               default = snakemake@input[["rds"]]) %>%
  add_argument("--output-dir",
               help = "Path to the output directory for filtered Cell Ranger files",
               type = "character",
               default = dirname(snakemake@output[["barcodes"]])) %>%
  add_argument("--output-csv", 
               help = "Path to save the filtering statistics CSV file", 
               type = "character",
               default = snakemake@output[["filter_metrics"]]) %>%
  add_argument("--min-genes",
               help = "Minimum number of genes per cell. Set to -1 to disable.",
               type = "integer",
               default = snakemake@params[["min_genes"]]) %>%
  add_argument("--max-mito",
               help = "Maximum mitochondrial percentage per cell. Set to -1.0 to disable.",
               type = "double",
               default = snakemake@params[["max_mito"]]) %>%
  add_argument("--min-umi",
               help = "Minimum UMI count per cell. Set to -1 to disable.",
               type = "integer",
               default = snakemake@params[["min_umi"]]) %>%
  add_argument("--capture-id",
               help = "Capture ID for logging and reporting (derived from wildcard)",
               type = "character",
               default = snakemake@wildcards[["capture"]]) %>%
  add_argument("--log-file",
               help = "Path to the log file (defaults to Snakemake log file when run via Snakemake).",
               type = "character",
               default = snakemake@log[[1]]) %>%
  parse_args()

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

to_dgc <- function(mat) {
  if (!is(mat, "dgCMatrix")) as(mat, "dgCMatrix") else mat
}
# Write data to Cell Ranger format
# gene.id should be the Ensembl ID
#     NOTE ON THIS: The use of Read10x in the previous script removes the Ensembl ID. 
#     If we need Ensembl IDs, a fix will be needed in the previous script
#     such as adding Ensembl IDs to the object metadata and then using that here.
# gene.symbol should be the gene name
# gene.type should be the type of gene (e.g., "Gene Expression")
write_10x <- function(mat, path) {
    gene.names   <- rownames(mat)
    # Using placeholder if Ensembl IDs are not available or not consistently named 'gene.id' in input
    gene.ids <- if ("gene.id" %in% colnames(rownames(mat))) rownames(mat)$gene.id else paste0("unknown_", seq_len(nrow(mat)))
    barcodes   <- colnames(mat)
    DropletUtils::write10xCounts(
        path       = path,
        x          = to_dgc(mat), 
        gene.id    = gene.ids,
        gene.symbol= gene.names,
        gene.type  = rep("Gene Expression", length(gene.ids)),
        barcodes   = barcodes,
        type       = "sparse",
        version    = "3",
        overwrite  = TRUE
    )
}

# --- Main Workflow ---
capture_id <- arguments$capture_id
input_rds <- arguments$input_rds
output_dir <- arguments$output_dir
output_csv_path <- arguments$output_csv 
min_genes_thresh <- arguments$min_genes
max_mito_thresh <- arguments$max_mito
min_umi_thresh <- arguments$min_umi

if (min_genes_thresh < -1) stop("min-genes must be -1 or >=0")
if (max_mito_thresh < -1.0 || max_mito_thresh > 100.0) stop("max-mito must be -1.0 or between 0.0 and 100.0")
if (min_umi_thresh < -1) stop("min-umi must be -1 or >=0")

message(sprintf("Starting filtering for capture: %s", capture_id))
message(sprintf("Input Seurat RDS: %s", input_rds))
message(sprintf("Output Cell Ranger directory: %s", output_dir))
message(sprintf("Output filtering statistics CSV: %s", output_csv_path)) 
message(sprintf("Filter Thresholds: min_genes= %s, max_mito= %s, min_umi= %s (-1 means disabled)",
                ifelse(min_genes_thresh == -1, "Disabled", as.character(min_genes_thresh)),
                ifelse(max_mito_thresh == -1.0, "Disabled", sprintf("%.1f%%", max_mito_thresh)),
                ifelse(min_umi_thresh == -1, "Disabled", as.character(min_umi_thresh))))

# Data frame to store filtering outcomes
stats_df <- data.frame(
    total_initial_cells = NA_integer_,
    cells_discarded_by_min_gene_filter = NA_integer_, 
    cells_discarded_by_max_mito_filter = NA_integer_, 
    cells_discarded_by_min_umi_filter = NA_integer_, 
    total_final_cells_after_filters = NA_integer_,
    proportion_discarded_after_min_gene_filter = NA_real_,
    proportion_discarded_after_max_mito_filter = NA_real_,
    proportion_discarded_after_min_umi_filter = NA_real_,
    total_proportion_discarded = NA_real_
)

tryCatch({
    # Load Seurat object
    message("Loading Seurat object...")
    seurat_object <- readRDS(input_rds)
    if (is.null(seurat_object)) {
        stop(paste("Failed to load Seurat object from:", input_rds), call.=FALSE)
    }
    initial_cell_count <- ncol(seurat_object)
    message(sprintf("Loaded object with %d cells.", initial_cell_count))
    
    stats_df$total_initial_cells <- initial_cell_count
    
    if (initial_cell_count == 0) {
        message("Input Seurat object has 0 cells. Skipping filtering.")
        applied_filters_str <- "None (0 initial cells)"
        
        stats_df$cells_discarded_by_min_gene_filter <- 0
        stats_df$cells_discarded_by_max_mito_filter <- 0 
        stats_df$cells_discarded_by_min_umi_filter <- 0 
        stats_df$total_final_cells_after_filters <- 0
        stats_df$proportion_discarded_after_min_gene_filter <- 0.0
        stats_df$proportion_discarded_after_max_mito_filter <- 0.0
        stats_df$proportion_discarded_after_min_umi_filter <- 0.0
        stats_df$total_proportion_discarded <- 0.0
        
        # Write empty Cell Ranger output
        message("Writing empty Cell Ranger output files...")
        if (nrow(seurat_object) == 0) {
            empty_counts <- Matrix::Matrix(0, nrow = 1, ncol = 0, sparse = TRUE)
            rownames(empty_counts) <- c("DUMMY_GENE")
        } else {
            empty_counts <- GetAssayData(seurat_object, layer = "counts")[, 0, drop=FALSE]
        }
        write_10x(mat = empty_counts, path = output_dir)
        
        # Write filtering statistics CSV file
        message(sprintf("Saving filtering statistics to %s", output_csv_path))
        write.csv(stats_df, file = output_csv_path, row.names = FALSE, quote = FALSE)
        message("Filtering statistics CSV and empty output files written.")

    } else {
        # Check if necessary metadata exists (should be calculated in Script 1 `pdmx_convert_seurat.R`)
         if (!("percent.mt" %in% colnames(seurat_object@meta.data))) {
             stop("Metadata column 'percent.mt' not found. Ensure pdmx_convert_seurat.R ran correctly.", call.=FALSE)
         }
        if (!("nFeature_RNA" %in% colnames(seurat_object@meta.data))) {
            stop("Metadata column 'nFeature_RNA' not found.", call.=FALSE)
        }
         if (!("nCount_RNA" %in% colnames(seurat_object@meta.data))) {
            stop("Metadata column 'nCount_RNA' not found.", call.=FALSE)
        }

        # Apply filters sequentially
        cells_to_keep_logical <- rep(TRUE, initial_cell_count) 
        applied_filters <- c()
        
        # --- Filter 1: Minimum genes per cell ---
        cells_count_before_current_filter <- sum(cells_to_keep_logical)
        if (min_genes_thresh != -1 && min_genes_thresh >= 0) {
            message(sprintf("Applying filter: nFeature_RNA >= %d", min_genes_thresh))
            cells_passing_current_filter <- seurat_object$nFeature_RNA >= min_genes_thresh
            message(sprintf("  %d / %d cells would pass this specific filter if applied alone to current set.", sum(cells_to_keep_logical & cells_passing_current_filter), sum(cells_to_keep_logical)))
            cells_to_keep_logical <- cells_to_keep_logical & cells_passing_current_filter
            applied_filters <- c(applied_filters, sprintf("min_genes >= %d", min_genes_thresh))
        } else {
            message("Skipping filter: Minimum genes per cell (value was -1).")
        }
        cells_remaining_after_current_filter <- sum(cells_to_keep_logical)
        stats_df$cells_discarded_by_min_gene_filter <- cells_count_before_current_filter - cells_remaining_after_current_filter
        stats_df$proportion_discarded_after_min_gene_filter <- if (cells_count_before_current_filter > 0) stats_df$cells_discarded_by_min_gene_filter / cells_count_before_current_filter else 0.0
        message(sprintf("  Cells remaining after min gene filter stage: %d. Discarded at this step: %d.", cells_remaining_after_current_filter, stats_df$cells_discarded_by_min_gene_filter))

        # --- Filter 2: Maximum mitochondrial percentage ---
        cells_count_before_current_filter <- sum(cells_to_keep_logical) # Cells that passed previous filters
        if (max_mito_thresh != -1.0 && max_mito_thresh <= 100 && max_mito_thresh >= 0) {
            message(sprintf("Applying filter: percent.mt <= %.1f%%", max_mito_thresh))
            percent_mt_values <- seurat_object$percent.mt
            percent_mt_values[is.na(percent_mt_values)] <- 0 
            cells_passing_current_filter <- percent_mt_values <= max_mito_thresh
            message(sprintf("  %d / %d cells would pass this specific filter if applied alone to current set.", sum(cells_to_keep_logical & cells_passing_current_filter), sum(cells_to_keep_logical)))
            cells_to_keep_logical <- cells_to_keep_logical & cells_passing_current_filter
            applied_filters <- c(applied_filters, sprintf("max_mito <= %.1f%%", max_mito_thresh))
        } else {
            message("Skipping filter: Maximum mitochondrial percentage (value was -1.0 or invalid).")
        }
        cells_remaining_after_current_filter <- sum(cells_to_keep_logical)
        stats_df$cells_discarded_by_max_mito_filter <- cells_count_before_current_filter - cells_remaining_after_current_filter
        stats_df$proportion_discarded_after_max_mito_filter <- if (cells_count_before_current_filter > 0) stats_df$cells_discarded_by_max_mito_filter / cells_count_before_current_filter else 0.0
        message(sprintf("  Cells remaining after max mito filter stage: %d. Discarded at this step: %d.", cells_remaining_after_current_filter, stats_df$cells_discarded_by_max_mito_filter))
        
        # --- Filter 3: Minimum UMI count ---
        cells_count_before_current_filter <- sum(cells_to_keep_logical) # Cells that passed previous filters
        if (min_umi_thresh != -1 && min_umi_thresh >= 0) {
            message(sprintf("Applying filter: nCount_RNA >= %d", min_umi_thresh))
            cells_passing_current_filter <- seurat_object$nCount_RNA >= min_umi_thresh
            message(sprintf("  %d / %d cells would pass this specific filter if applied alone to current set.", sum(cells_to_keep_logical & cells_passing_current_filter), sum(cells_to_keep_logical)))
            cells_to_keep_logical <- cells_to_keep_logical & cells_passing_current_filter
            applied_filters <- c(applied_filters, sprintf("min_umi >= %d", min_umi_thresh))
        } else {
            message("Skipping filter: Minimum UMI count (value was -1).")
        }
        cells_remaining_after_current_filter <- sum(cells_to_keep_logical)
        stats_df$cells_discarded_by_min_umi_filter <- cells_count_before_current_filter - cells_remaining_after_current_filter
        stats_df$proportion_discarded_after_min_umi_filter <- if (cells_count_before_current_filter > 0) stats_df$cells_discarded_by_min_umi_filter / cells_count_before_current_filter else 0.0
        message(sprintf("  Cells remaining after min UMI filter stage: %d. Discarded at this step: %d.", cells_remaining_after_current_filter, stats_df$cells_discarded_by_min_umi_filter))

        # Subset the object
        seurat_filtered <- seurat_object[, cells_to_keep_logical]
        final_cell_count <- ncol(seurat_filtered)
        stats_df$total_final_cells_after_filters <- final_cell_count
        
        cells_discarded_total <- initial_cell_count - final_cell_count
        proportion_discarded_total_calc <- if (initial_cell_count > 0) cells_discarded_total / initial_cell_count else 0.0
        stats_df$total_proportion_discarded <- proportion_discarded_total_calc

        applied_filters_str <- if(length(applied_filters) > 0) paste(applied_filters, collapse=", ") else "None"

        message(sprintf("Filtering complete. Kept %d / %d cells.", final_cell_count, initial_cell_count))
        message(sprintf("%.2f%% of cells discarded from %s after applying filters: %s",
                        stats_df$total_proportion_discarded * 100,
                        capture_id,
                        applied_filters_str))

        # Save filtering statistics as a CSV file
        message(sprintf("Saving filtering statistics to %s", output_csv_path))
        write.csv(stats_df, file = output_csv_path, row.names = FALSE, quote = FALSE)

        # Save filtered data in Cell Ranger format
        message("Writing filtered data to Cell Ranger v3 format...")
        if (final_cell_count == 0) {
            message("No cells remaining after filtering. Writing empty output.")
            if (nrow(seurat_filtered) == 0) { 
                empty_counts <- Matrix::Matrix(0, nrow = 1, ncol = 0, sparse = TRUE)
                rownames(empty_counts) <- c("DUMMY_GENE")
            } else {
                empty_counts <- GetAssayData(seurat_filtered, layer = "counts")[, 0, drop=FALSE]
            }
            write_10x(mat = empty_counts, path = output_dir)
        } else {
            # Extract counts for writing.
            # pdmx_convert_seurat.R ensures the input RDS carries a
            # single-layer counts assay (in multi mode, only the Gene
            # Expression matrix is loaded), so the plain layer = "counts"
            # lookup is valid for both count and multi modes.
            counts_to_write <- GetAssayData(seurat_filtered, layer = "counts")
            write_10x(mat = counts_to_write, path = output_dir)
        }
        message("Filtered Cell Ranger files successfully written.")
    } # End else block for initial_cell_count > 0

}, error = function(e) {
    message(sprintf("Error during filtering for %s: %s", capture_id, e$message))
    # Attempt to write partial stats if some were computed
    if (!all(is.na(stats_df$total_initial_cells))) { # Check if initial count was set
         message(sprintf("Attempting to write available statistics to %s due to error.", output_csv_path))
         write.csv(stats_df, file = output_csv_path, row.names = FALSE, quote = FALSE)
    }
    stop(e$message, call.=FALSE) # Re-throw the error to ensure Snakemake catches it
})

# Remove the features.tsv.gz file from output_dir, to allow later replacement 
# with its original version (restoring Ensembl IDs)
features_file <- file.path(output_dir, "features.tsv.gz")
if (file.exists(features_file)) {
    message(sprintf("Removing features.tsv.gz file from output directory: %s", features_file))
    file.remove(features_file)
} else {
    message(sprintf("features.tsv.gz file not found in output directory: %s", features_file))
}

message(sprintf("Successfully completed filtering for capture: %s", capture_id))
