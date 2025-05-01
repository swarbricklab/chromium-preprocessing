#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
#  Pre-demux - Cell Filtering
# -----------------------------------------------------------------------------
#  Goal   : Remove very low‑quality cells from Cell Ranger outputs before SNP
#           demultiplexing, assuming that these affect performance.
#
#  Inputs  : One or more Cell Ranger ouput folders (each folder = one sample/pool)
#  Outputs : • Cell Ranger output files (barcodes/features/matrix) for every pool 
#              (ONLY IF the --tuning flag is NOT supplied and only one thresholds
#              combination is provided)
#            • Threshold tuning metrics/charts when the --tuning flag is supplied,
#              alongisde an overall CSV ranking threshold combinations by the average
#              proportion of cells discarded across pools.
#  Config  : A single YAML file holding paths and zero/one/list of values for
#            the three filter thresholds (minimum genes per cell, max mitochondrial 
#            percentage, minimum UMI count). 
#
#  Usage   : Rscript filter_cellranger.R --config config.yaml [--tuning]

suppressPackageStartupMessages({
  library(argparser)     
  library(yaml)          
  library(Seurat)        
  library(SeuratObject)  
  library(readr)         
  library(dplyr)         
  library(tidyr)        
  library(tibble)        
  library(DropletUtils)
})

# ──────────────────────────────────────────────────────────────────────────────
# 2. Functions for filtering and metrics calculation                                                        
# ──────────────────────────────────────────────────────────────────────────────

# Identifying cells/genes discarded by filtering
calculate_filter_metrics <- function(seurat_before, seurat_after){
  cells_before <- ncol(seurat_before); cells_after <- ncol(seurat_after)
  genes_before <- nrow(seurat_before); genes_after <- nrow(seurat_after)
  tibble(
    cells_kept = cells_after,
    cells_discarded = cells_before - cells_after,
    proportion_cells_discarded = if(cells_before > 0) (cells_before - cells_after) / cells_before else NA_real_,
    genes_kept = genes_after,
    genes_discarded = genes_before - genes_after,
    proportion_genes_discarded = if(genes_before > 0) (genes_before - genes_after) / genes_before else NA_real_
  )
}

# Similar to function above, but at the capture level
# This function assumes that the barcodes are formatted as "cellID-captureID"
# Note: we'll need to change this depending on the barcoding scheme used
calculate_capture_metrics <- function(seurat_before, seurat_after){
  get_suffix <- function(barcode) sub(".*-", "", barcode)

  barcodes_before <- colnames(seurat_before)
  barcodes_after <- colnames(seurat_after)

  # Cells per capture
  cells_before_tbl <- tibble(capture_id = get_suffix(barcodes_before)) %>%
    group_by(capture_id) %>% summarise(cells_before = n(), .groups = "drop")
  cells_after_tbl  <- tibble(capture_id = get_suffix(barcodes_after))  %>%
    group_by(capture_id) %>% summarise(cells_after = n(),  .groups = "drop")

  capture_df <- full_join(cells_before_tbl, cells_after_tbl, by = "capture_id") %>%
    replace_na(list(cells_before = 0L, cells_after = 0L)) %>%
    mutate(cells_discarded = cells_before - cells_after,
           proportion_cells_discarded = if_else(cells_before > 0, cells_discarded / cells_before, NA_real_))

  # Genes per capture
  counts_before <- GetAssayData(seurat_before, layer = "counts")
  counts_after <- GetAssayData(seurat_after,  layer = "counts")

  # We include expressions of 0, checking that genes aren't discarded
  capture_df %>% rowwise() %>%
    mutate(
      genes_before = sum(rowSums(counts_before[, barcodes_before[get_suffix(barcodes_before) == capture_id], drop = FALSE]) >= 0),
      genes_after = sum(rowSums(counts_after [, barcodes_after [get_suffix(barcodes_after)  == capture_id], drop = FALSE]) >= 0),
      genes_kept = genes_after,
      genes_discarded = genes_before - genes_after,
      proportion_genes_discarded = if_else(genes_before > 0, genes_discarded / genes_before, NA_real_)
    ) %>% ungroup() %>%
    select(capture_id, cells_discarded, proportion_cells_discarded,
           genes_kept, genes_discarded, proportion_genes_discarded)
}

# ──────────────────────────────────────────────────────────────────────────────
# 3. Plot helpers                                                               
# ──────────────────────────────────────────────────────────────────────────────

plot_filter_barplot <- function(metric_tbl, label, pool_name){
  vals <- c(metric_tbl$cells_kept, metric_tbl$cells_discarded)
  names(vals) <- c("Kept", "Discarded")
  bars <- barplot(vals, main = paste("Filtering", label, "- Pool:", pool_name),
                  ylab = "Number of Cells", ylim = c(0, max(vals) * 1.2))
  text(bars, vals, labels = vals, pos = 3, cex = 0.8)
}

save_filter_barplot <- function(metric_tbl, label, output_dir, pool_name){
  png(file.path(output_dir, paste0(label, "_barplot.png")))
  plot_filter_barplot(metric_tbl, label, pool_name)
  dev.off()
}

plot_capture_barplot <- function(capture_tbl, label, pool_name){
  barplot(rbind(Kept = capture_tbl$cells_after, Discarded = capture_tbl$cells_discarded),
          main = paste("Filter: ", label, " for Pool:", pool_name),
          ylab = "Number of Cells", legend = TRUE, las = 2, cex.names = 0.8)
}

save_capture_barplot <- function(capture_tbl, label, output_dir, pool_name){
  png(file.path(output_dir, paste0(label, "_captures_barplot.png")), width = 1200, height = 800, res = 120)
  plot_capture_barplot(capture_tbl, label, pool_name)
  dev.off()
}

save_csv_table <- function(tbl, label, directory) write_csv(tbl, file.path(directory, paste0(label, "_metrics.csv")))

# ──────────────────────────────────────────────────────────────────────────────
# 4. Main workflow                                                             
# ──────────────────────────────────────────────────────────────────────────────

main <- function(){
  # ---- 4.1  Parse command‑line arguments ------------------------------------
  parser <- arg_parser("Pre‑demux Cell Filtering") |>
    add_argument("--config", "Path to YAML configuration file", type = "character") |>
    add_argument("--tuning", "Enable metrics/chart creation for threshold tuning", flag = TRUE)
  arguments <- parse_args(parser)

  # ---- 4.2  Load YAML config -------------------------------------------------
  config <- yaml::read_yaml(arguments$config)
  input_root_path   <- config$cellranger_input_path
  output_root_path  <- config$cellranger_output_path
  output_subfolder_path <- config$output_subfolder_path
  figures_output_path <- config$figures_output_path
  samplesheet <- config$samplesheet
  cellranger_subfolder <- config$cellranger_subfolder

  # Since thresholds can be either empty, a scalar or vector, we parse them
  parse_threshold <- function(x){
    if(is.null(x) || length(x) == 0 || all(is.na(x) | x == "")) return(NA)
    unlist(x)
  }
  min_genes_list <- parse_threshold(config$filter_params$min_genes)
  max_mito_list  <- parse_threshold(config$filter_params$max_mito)
  min_umi_list   <- parse_threshold(config$filter_params$min_umi)

  threshold_grid <- expand.grid(min_genes = if(is.na(min_genes_list[1])) NA else min_genes_list,
                                max_mito = if(is.na(max_mito_list[1]))  NA else max_mito_list,
                                min_umi = if(is.na(min_umi_list[1]))   NA else min_umi_list,
                                KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  if(nrow(threshold_grid) == 0){
    threshold_grid <- tibble(min_genes = NA_real_, max_mito = NA_real_, min_umi = NA_real_)
  }

  # if not in tuning mode, allow only one threshold combination
  if (!arguments$tuning && nrow(threshold_grid) > 1) {
    stop("Multiple threshold combinations found. Please use --tuning to help select one.")
  } 

  # ---- 4.3 Checks & folder prep --------------------------------------
  if(!dir.exists(input_root_path)) stop("Input path does not exist: ", input_root_path)

  if (!arguments$tuning) {
    dir.create(output_root_path,  recursive = TRUE, showWarnings = FALSE)
  }

  if (arguments$tuning) {
    dir.create(figures_output_path, recursive = TRUE, showWarnings = FALSE)
  }

  if(!is.null(samplesheet)){
    samplesheet <- read_csv(samplesheet, col_names = TRUE, show_col_types = FALSE)
    pool_directories <- file.path(input_root_path, samplesheet$pool_id)
  }

  # Stop if no captures/pools are found
  if(is.null(pool_directories) || length(pool_directories) == 0){
    stop("No pool directories found in: ", input_root_path, "or in the samplesheet.")
  }

  message("\nStarting pre‑demux filtering for ", length(pool_directories), " pool(s)…")

  # To store summaries per threshold combination
  combo_summary_list <- list()

  # ---- 4.4  Iterate over threshold combos -----------------------------------
  for(combo_idx in seq_len(nrow(threshold_grid))){
    current_combo <- threshold_grid[combo_idx, ]
    min_genes <- current_combo$min_genes
    max_mito <- current_combo$max_mito
    min_umi <- current_combo$min_umi

    # Assign folder names that identify thresholds e.g. [gen10][mit20][umi100]
    combo_label <- paste0("[gen", ifelse(is.na(min_genes), "NA", min_genes), "]",
                          "[mit", ifelse(is.na(max_mito), "NA", max_mito),  "]",
                          "[umi", ifelse(is.na(min_umi), "NA", min_umi),   "]")

    message("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    message("Applying filter combination ", combo_idx, " / ", nrow(threshold_grid), " --> ", combo_label)

    combo_fig_root <- file.path(figures_output_path, combo_label)

    if (arguments$tuning) {
      dir.create(combo_fig_root, recursive = TRUE, showWarnings = FALSE)
    }

    # Accumulate metrics across pools for this combination --------------------
    overall_metrics_list <- list()

    # ---- 4.4.1 Iterate over pools for this threshold combo ------------------
    for(pool_directory in pool_directories){
      pool_name <- basename(pool_directory)
      message("\nPool: ", pool_name)

      # Gracefully handle cases where subfolder names are not provided
      if (is.null(cellranger_subfolder) || cellranger_subfolder == "") {
        pool_input_path <- pool_directory
      } else {
        pool_input_path <- file.path(pool_directory, cellranger_subfolder)
      }

      if (is.null(output_subfolder_path) || output_subfolder_path == "") {
        pool_output_path <- file.path(output_root_path, pool_name)
      } else {
        pool_output_path <- file.path(output_root_path, pool_name, output_subfolder_path)
      }

      pool_figures_dir <- file.path(combo_fig_root, pool_name)
      capture_fig_dir <- file.path(pool_figures_dir, "captures")

      if (!arguments$tuning){
        dir.create(pool_output_path, recursive = TRUE, showWarnings = FALSE)
      }
      if (arguments$tuning){
        dir.create(pool_figures_dir, recursive = TRUE, showWarnings = FALSE)
        dir.create(capture_fig_dir, recursive = TRUE, showWarnings = FALSE)
      }

      # ---- 4.4.1.1  Read Cell Ranger input ---------------------------------
      message("  Reading Cell Ranger input…")

      counts_matrix <- Read10X(data.dir = pool_input_path)
      seurat_object <- CreateSeuratObject(counts = counts_matrix)

      # ---- 4.4.1.2  Annotations  -------------------------------------------
      seurat_object[["percent.mt"]] <- PercentageFeatureSet(seurat_object, pattern = "^MT-")
      seurat_object$capture_id <- sub(".*-", "", colnames(seurat_object))
      original_seurat_object <- seurat_object

      # ---- 4.4.1.3 Apply Filters ------------------------------------------

      # If tuning is disabled, perform all filters in one go
      if(!arguments$tuning){
        message("  Applying filters without creating metrics/charts…")
        # Apply filters only if thresholds are not NA
        filter_expr <- rep(TRUE, ncol(seurat_object))
        if (!is.na(min_genes)) {filter_expr <- filter_expr & (seurat_object$nFeature_RNA >= min_genes)}
        if (!is.na(max_mito)) {filter_expr <- filter_expr & (seurat_object$percent.mt <= max_mito)}
        if (!is.na(min_umi)) {filter_expr <- filter_expr & (seurat_object$nCount_RNA >= min_umi)}
        seurat_object <- seurat_object[, filter_expr]
        message("  Writing filtered CellRanger outputs...")
        DropletUtils::write10xCounts(path = pool_output_path, overwrite = TRUE,
          x = GetAssayData(seurat_object, layer = "counts"), version = "3")
        message("✔ Completed pool: ", pool_name)
        next
      }

      # Filter 1: min genes per cell -------------------------------------------
      if(!is.na(min_genes)){
        message(sprintf("  Filter 1 | genes ≥ %d", min_genes))
        # To avoid any potential gene loss with subset, I'm using WhichCells
        seurat_after_gene_filter <- seurat_object[, WhichCells(seurat_object, expression = nFeature_RNA >= min_genes)]
        if(arguments$tuning){
          metrics_gene_filter <- calculate_filter_metrics(seurat_object, seurat_after_gene_filter)
          save_filter_barplot(metrics_gene_filter, "1-genes_per_cell", pool_figures_dir, pool_name)
          save_csv_table(metrics_gene_filter, "1-genes_per_cell", pool_figures_dir)
        }
      } else {
        seurat_after_gene_filter <- seurat_object
      }

      # Filter 2: max mitochondrial percentage ---------------------------------
      if(!is.na(max_mito)){
        message(sprintf("  Filter 2 | mito ≤ %.1f%%", max_mito))
        seurat_after_mito_filter <- seurat_after_gene_filter[, WhichCells(seurat_after_gene_filter, expression = percent.mt <= max_mito)]
        if(arguments$tuning){
          metrics_mito_filter <- calculate_filter_metrics(seurat_after_gene_filter, seurat_after_mito_filter)
          save_filter_barplot(metrics_mito_filter, "2-mito_percentage", pool_figures_dir, pool_name)
          save_csv_table(metrics_mito_filter, "2-mito_percentage", pool_figures_dir)
        }
      } else {
        seurat_after_mito_filter <- seurat_after_gene_filter
      }

      # Filter 3: min UMIs --------------------------------------------------------
      if(!is.na(min_umi)){
        message(sprintf("  Filter 3 | UMIs ≥ %d", min_umi))
        seurat_after_umi_filter <- seurat_after_mito_filter[, WhichCells(seurat_after_mito_filter, expression = nCount_RNA >= min_umi)]
        if(arguments$tuning){
          metrics_umi_filter <- calculate_filter_metrics(seurat_after_mito_filter, seurat_after_umi_filter)
          save_filter_barplot(metrics_umi_filter, "3-min_umi", pool_figures_dir, pool_name)
          save_csv_table(metrics_umi_filter, "3-min_umi", pool_figures_dir)
        }
      } else {
        seurat_after_umi_filter <- seurat_after_mito_filter
      }

      # ---- 4.4.1.4  Overall metrics per pool ------------------------------------
      if(arguments$tuning){
        overall_metrics <- calculate_filter_metrics(original_seurat_object, seurat_after_umi_filter)
        save_filter_barplot(overall_metrics, "overall", pool_figures_dir, pool_name)
        save_csv_table(overall_metrics, "overall", pool_figures_dir)

        capture_metrics <- calculate_capture_metrics(original_seurat_object, seurat_after_umi_filter)
        save_csv_table(capture_metrics, "overall_captures", capture_fig_dir)
        overall_metrics_list[[pool_name]] <- overall_metrics |> mutate(pool = pool_name)
      }

      message("✔ Completed pool: ", pool_name)
    }

    # ---- 4.4.2  Summary for these thresholds ---------------------------------
    if(arguments$tuning && length(overall_metrics_list)){
      combo_summary <- bind_rows(overall_metrics_list) |>
        summarise(
          total_cells_discarded = sum(cells_discarded, na.rm = TRUE),
          total_cells_kept = sum(cells_kept, na.rm = TRUE),
          mean_prop_cells_discarded = mean(proportion_cells_discarded, na.rm = TRUE),
          sd_prop_cells_discarded = sd(  proportion_cells_discarded, na.rm = TRUE)
        ) |>
        mutate(combo = combo_label, .before = 1)
            combo_summary_list[[combo_label]] <- combo_summary

      # Write summary table ---------------------------------------------------
      write_csv(combo_summary, file.path(combo_fig_root, "summary_metrics_across_pools.csv"))
    }
  }

  # ---- 4.5  Global summary across all threshold combos  ----------------------
  if(arguments$tuning && length(combo_summary_list)){
    final_summary_tbl <- bind_rows(combo_summary_list) |>
      arrange(desc(mean_prop_cells_discarded))
    write_csv(final_summary_tbl, file.path(figures_output_path, "all_combinations_summary.csv"))
  }

  message("\nAll pools processed successfully!\n")
}

main()
