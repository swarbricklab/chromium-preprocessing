#!/usr/bin/env Rscript
# Predemux Script 1: Convert Cell Ranger output to Seurat Object RDS file
# Calculates 'percent.mt' and adds it to the object metadata.
# Date Updated: 7/5/2025

# Known issues:
# 1. When using cellranger multi, the Seurat object is saved with several count layers (one for each type of data).
#    This leads to issues during cell filtering. 
# 2. Read10x stores gene names, but not Ensembl IDs. This affects the reconstruction of
#   features.tsv.tz 

library(argparser)
suppressPackageStartupMessages({
  library(Seurat)
  library(SeuratObject)
  library(Matrix)
})

p <- arg_parser("Convert Cell Ranger output to Seurat Object RDS and add mitochondrial percentage")
p <- add_argument(p, "--input-dir", help="Path to the Cell Ranger output directory (containing matrix.mtx.gz, features.tsv.gz, barcodes.tsv.gz)", type="character")
p <- add_argument(p, "--output-rds", help="Path to save the output Seurat object RDS file", type="character")
p <- add_argument(p, "--mito-pattern", help="Regex pattern to identify mitochondrial genes", default="^MT-", type="character")
p <- add_argument(p, "--log-file", help="Path to the log file", type="character", default=NULL)
p <- add_argument(p, "--capture-id", help="Capture ID for logging", type="character", default="unknown_capture")

arguments <- parse_args(p)

# --- Validation of Snakemake Directory Settings ---
if (is.na(arguments$input_dir) || is.na(arguments$output_rds)){
  print(p)
  stop("Input directory (--input-dir) and output RDS path (--output-rds) must be supplied.", call.=FALSE)
}
if (!dir.exists(arguments$input_dir)) {
    stop(paste("Input directory does not exist:", arguments$input_dir), call.=FALSE)
}

# --- Logging Setup ---
# Use sink to redirect output and messages to a log file
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
input_dir <- arguments$input_dir
output_rds <- arguments$output_rds
mito_pattern <- arguments$mito_pattern

message(sprintf("Starting Seurat object creation for capture: %s", capture_id))
message(sprintf("Input Cell Ranger directory: %s", input_dir))
message(sprintf("Output RDS file: %s", output_rds))
message(sprintf("Mitochondrial gene pattern: %s", mito_pattern))


tryCatch({
    # Read Cell Ranger data
    message("Reading 10X data...")
    counts_matrix <- Read10X(data.dir = input_dir)
    # Catch empty objects
    if (is.null(counts_matrix) || length(counts_matrix) == 0) {
        stop("Read10X did not return a valid matrix. Check input directory structure and files.", call.=FALSE)
    }
    initial_dims <- dim(counts_matrix)
    message(sprintf("Initial matrix dimensions: %d genes x %d cells", initial_dims[1], initial_dims[2]))

    # Create Seurat object
    message("Creating Seurat object...")
    # CreateSeuratObject expects a matrix. With multi, it will likely be a list of matrices
    # To add multi compatability, I think we'd have to check if counts_matrix is a list
    # and then find the matrix corresponding to gene expression??
    seurat_object <- CreateSeuratObject(counts = counts_matrix)
    message(sprintf("Seurat object created with %d genes and %d cells.", nrow(seurat_object), ncol(seurat_object)))

    # Calculate and add mitochondrial percentage
    if (ncol(seurat_object) > 0) {
        message("Calculating mitochondrial percentage ('percent.mt')...")
        seurat_object[["percent.mt"]] <- PercentageFeatureSet(seurat_object, pattern = mito_pattern)
        message(sprintf("Added 'percent.mt' metadata. Mean value: %.2f%%", mean(seurat_object$percent.mt, na.rm=TRUE)))
    } else {
        message("Skipping mitochondrial percentage calculation (0 cells). Adding empty 'percent.mt' column.")
        seurat_object$percent.mt <- numeric(0) # Add empty column to maintain structure
    }

    # Identify memory usage of the Seurat object
    message("Calculating Seurat object size in memory...")
    obj_size <- object.size(seurat_object)                     # bytes
    msg_size <- format(obj_size, units = "auto")               # e.g. "1.3 Gb"
    message(sprintf("Seurat object size in memory: %s", msg_size))

    # Save Seurat object
    message("Saving Seurat object to RDS file...")
    saveRDS(seurat_object, file = output_rds)
    message("Seurat object successfully saved.")

}, error = function(e) {
    message(sprintf("Error during Seurat object creation for %s: %s", capture_id, e$message))
    stop(e$message, call.=FALSE) # Stop execution on error
})

message(sprintf("Successfully completed Seurat object creation for capture: %s", capture_id))
