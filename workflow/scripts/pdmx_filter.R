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

p <- arg_parser("Apply filters to Seurat object and save outputs")
p <- add_argument(p, "--input-rds", help="Path to the input Seurat object RDS file", type="character")
p <- add_argument(p, "--output-dir", help="Path to the output directory for filtered Cell Ranger files", type="character")
p <- add_argument(p, "--output-txt", help="Path to save the proportion discarded text file", type="character")
p <- add_argument(p, "--min-genes", help="Minimum number of genes per cell. Set to -1 to disable.", type="integer", default=-1)
p <- add_argument(p, "--max-mito", help="Maximum mitochondrial percentage per cell. Set to -1.0 to disable.", type="double", default=-1.0)
p <- add_argument(p, "--min-umi", help="Minimum UMI count per cell. Set to -1 to disable.", type="integer", default=-1)
p <- add_argument(p, "--capture-id", help="Capture ID for logging and reporting", type="character", default="unknown_capture")
p <- add_argument(p, "--log-file", help="Path to the log file", type="character", default=NULL)

arguments <- parse_args(p)

# --- Validation ---
# TODO: Consider removing (Snakemake will handle this)
if (is.na(arguments$input_rds) || is.na(arguments$output_dir) || is.na(arguments$output_txt)){
  print(p)
  stop("Input RDS (--input-rds), output directory (--output-dir), and output text file path (--output-txt) must be supplied.", call.=FALSE)
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
output_dir <- arguments$output_dir
output_txt <- arguments$output_txt
min_genes_thresh <- arguments$min_genes
max_mito_thresh <- arguments$max_mito
min_umi_thresh <- arguments$min_umi

message(sprintf("Starting filtering for capture: %s", capture_id))
message(sprintf("Input Seurat RDS: %s", input_rds))
message(sprintf("Output Cell Ranger directory: %s", output_dir))
message(sprintf("Output proportion discarded file: %s", output_txt))
message(sprintf("Filter Thresholds: min_genes= %s, max_mito= %s, min_umi= %s (-1 means disabled)",
                ifelse(min_genes_thresh == -1, "Disabled", as.character(min_genes_thresh)),
                ifelse(max_mito_thresh == -1.0, "Disabled", sprintf("%.1f%%", max_mito_thresh)),
                ifelse(min_umi_thresh == -1, "Disabled", as.character(min_umi_thresh))))

tryCatch({
    # Load Seurat object
    message("Loading Seurat object...")
    seurat_object <- readRDS(input_rds)
    if (is.null(seurat_object)) {
        stop(paste("Failed to load Seurat object from:", input_rds), call.=FALSE)
    }
    initial_cell_count <- ncol(seurat_object)
    message(sprintf("Loaded object with %d cells.", initial_cell_count))

    if (initial_cell_count == 0) {
        message("Input Seurat object has 0 cells. Skipping filtering.")
        proportion_discarded <- 0.0
        applied_filters_str <- "None (0 initial cells)"
        # Write empty Cell Ranger output
        message("Writing empty Cell Ranger output files...")
        # Create a minimal empty matrix structure expected by write10xCounts
        if (nrow(seurat_object) == 0) {
           empty_counts <- Matrix::Matrix(0, nrow = 1, ncol = 0, sparse = TRUE)
           rownames(empty_counts) <- c("DUMMY_GENE")
           empty_features <- data.frame(id="DUMMY_GENE", symbol="DUMMY_GENE", type="Gene Expression")
        } else {
           # Use existing genes but no cells
           empty_counts <- GetAssayData(seurat_object, layer = "counts")[, 0, drop=FALSE]
           empty_features <- data.frame(id=rownames(empty_counts), symbol=rownames(empty_counts), type="Gene Expression")
        }

        DropletUtils::write10xCounts(path = output_dir,
                                     x = empty_counts,
                                     barcodes = character(0), # Empty barcodes
                                     features = empty_features, # Need features df
                                     version = "3",
                                     overwrite = TRUE)
        # Write proportion discarded file
        writeLines(as.character(proportion_discarded), con = output_txt)
        message("Empty output files written.")

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
        cells_to_keep <- rep(TRUE, initial_cell_count)
        applied_filters <- c()

        # Filter 1: Minimum genes per cell
        if (min_genes_thresh != -1 && min_genes_thresh >= 0) { # Allow 0 as a valid threshold
            message(sprintf("Applying filter: nFeature_RNA >= %d", min_genes_thresh))
            cells_passing <- seurat_object$nFeature_RNA >= min_genes_thresh
            message(sprintf("  %d / %d cells remaining after this filter.", sum(cells_to_keep & cells_passing), sum(cells_to_keep)))
            cells_to_keep <- cells_to_keep & cells_passing
            applied_filters <- c(applied_filters, sprintf("min_genes >= %d", min_genes_thresh))
        } else {
            message("Skipping filter: Minimum genes per cell (value was -1).")
        }

        # Filter 2: Maximum mitochondrial percentage
        if (max_mito_thresh != -1.0 && max_mito_thresh <= 100 && max_mito_thresh >= 0) { # Allow 0 and 100
            message(sprintf("Applying filter: percent.mt <= %.1f%%", max_mito_thresh))
            # Handle potential NA values in percent.mt if some cells had 0 reads
            percent_mt_values <- seurat_object$percent.mt
            percent_mt_values[is.na(percent_mt_values)] <- 0 # Treat NA mito percent (0 reads) as passing
            cells_passing <- percent_mt_values <= max_mito_thresh
            message(sprintf("  %d / %d cells remaining after this filter.", sum(cells_to_keep & cells_passing), sum(cells_to_keep)))
            cells_to_keep <- cells_to_keep & cells_passing
            applied_filters <- c(applied_filters, sprintf("max_mito <= %.1f%%", max_mito_thresh))
        } else {
            message("Skipping filter: Maximum mitochondrial percentage (value was -1.0 or invalid).")
        }

        # Filter 3: Minimum UMI count
        if (min_umi_thresh != -1 && min_umi_thresh >= 0) { # Allow 0 as valid threshold
            message(sprintf("Applying filter: nCount_RNA >= %d", min_umi_thresh))
            cells_passing <- seurat_object$nCount_RNA >= min_umi_thresh
            message(sprintf("  %d / %d cells remaining after this filter.", sum(cells_to_keep & cells_passing), sum(cells_to_keep)))
            cells_to_keep <- cells_to_keep & cells_passing
            applied_filters <- c(applied_filters, sprintf("min_umi >= %d", min_umi_thresh))
        } else {
            message("Skipping filter: Minimum UMI count (value was -1).")
        }

        # Subset the object
        seurat_filtered <- seurat_object[, cells_to_keep]
        final_cell_count <- ncol(seurat_filtered)
        cells_discarded <- initial_cell_count - final_cell_count
        proportion_discarded <- if (initial_cell_count > 0) cells_discarded / initial_cell_count else 0.0

        applied_filters_str <- if(length(applied_filters) > 0) paste(applied_filters, collapse=", ") else "None"

        message(sprintf("Filtering complete. Kept %d / %d cells.", final_cell_count, initial_cell_count))
        message(sprintf("%.2f%% of cells discarded from %s after applying filters: %s",
                        proportion_discarded * 100,
                        capture_id,
                        applied_filters_str))

        # Save proportion discarded as a txt file (will be used in summary report)
        message(sprintf("Saving proportion discarded (%.6f) to %s", proportion_discarded, output_txt))
        # Use format to ensure standard decimal notation without unexpected scientific notation
        writeLines(format(proportion_discarded, scientific = FALSE, digits = 6, nsmall = 6), con = output_txt)


        # Save filtered data in Cell Ranger format
        # TODO: Validate this logic
        message("Writing filtered data to Cell Ranger v3 format...")
        if (final_cell_count == 0) {
             message("No cells remaining after filtering. Writing empty output.")
             # Create a minimal empty matrix structure expected by write10xCounts
             if (nrow(seurat_filtered) == 0) { # Should not happen if initial obj had genes
                empty_counts <- Matrix::Matrix(0, nrow = 1, ncol = 0, sparse = TRUE)
                rownames(empty_counts) <- c("DUMMY_GENE")
                empty_features <- data.frame(id="DUMMY_GENE", symbol="DUMMY_GENE", type="Gene Expression")
             } else {
                empty_counts <- GetAssayData(seurat_filtered, layer = "counts")[, 0, drop=FALSE]
                empty_features <- data.frame(id=rownames(empty_counts), symbol=rownames(empty_counts), type="Gene Expression")
             }
             DropletUtils::write10xCounts(path = output_dir,
                                           x = empty_counts,
                                           barcodes = character(0),
                                           features = empty_features,
                                           version = "3", overwrite = TRUE)
        } else {
            # Extract counts, features, barcodes for writing
            counts_to_write <- GetAssayData(seurat_filtered, layer = "counts")
            features_to_write <- data.frame(id = rownames(counts_to_write),
                                            symbol = rownames(counts_to_write), # Assuming IDs are symbols, adjust if gene symbols are elsewhere
                                            type = "Gene Expression")
            barcodes_to_write <- colnames(counts_to_write)

            DropletUtils::write10xCounts(path = output_dir,
                                          x = counts_to_write,
                                          version = "3",
                                          overwrite = TRUE)
        }
        message("Filtered Cell Ranger files successfully written.")
    } # End else block for initial_cell_count > 0

}, error = function(e) {
    message(sprintf("Error during filtering for %s: %s", capture_id, e$message))
    stop(e$message, call.=FALSE)
})

message(sprintf("Successfully completed filtering for capture: %s", capture_id))