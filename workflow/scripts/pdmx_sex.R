#!/usr/bin/env Rscript
# Predemux Script 5: Per-barcode sex typing (chrY panel + XIST)
#
# Emits one row per (filtered) barcode classifying it as
#   male | female | ambiguous | low_quality
# from chrY-unique gene expression and XIST, plus the continuous, signed
# `sex_score` and the raw counts so thresholds can be re-tuned downstream
# (strict for spike-in removal, lenient for QC) without re-running anything
# upstream.
#
# WHY HERE / WHAT IT READS
#   Runs on the KEPT predemux filtered 10x matrix
#   (predemux/<capture>/{matrix,barcodes,features}.tsv.gz). Because that matrix
#   is a persistent output, re-tuning sex thresholds re-runs ONLY this rule — no
#   cellranger, no Seurat rebuild. Cell filtering (min genes/UMI/mito) is on
#   cells, not genes, so XIST and every chrY marker survive into this matrix.
#
# METHOD (issue swarbricklab/chromium-preprocessing#126)
#   speckle::classifySex was the original suggestion, but it is GitHub-only
#   (not on bioconda) and returns only a bare Male/Female/NA label with no score
#   or confidence. We instead compute the call directly, which is conda-native
#   and yields the full schema the issue asks for:
#     - chrY_score = log1p(CP10K over the chrY-unique panel)  [depth-normalised]
#     - xist_score = log1p(CP10K of XIST)                     [depth-normalised]
#     - sex_score  = chrY_score - xist_score  (>0 male-leaning, <0 female-leaning)
#     - sex_call   from presence of chrY vs XIST signal, with an explicit
#                  `ambiguous` class (both present = possible cross-sex doublet,
#                  or neither present = undetermined) and a `low_quality` class
#                  for cells too shallow to call.
#     - confidence = |sex_score|, the margin from the chrY==XIST boundary.
#   The reference (refdata-gex-GRCh38-2020-A) hard-masks the chrY PAR, so PAR
#   reads map to chrX and the chrY-unique panel is clean of that false positive.

library(argparser)
suppressPackageStartupMessages({
  library(Matrix)
  library(dplyr)
  library(readr)
  library(tibble)
})

# --- Default chrY-unique markers (present & PAR-clean on GRCh38-2020-A) ---
DEFAULT_CHRY_MARKERS <- "RPS4Y1,DDX3Y,UTY,USP9Y,EIF1AY,KDM5D"
DEFAULT_XIST_GENE    <- "XIST"

# Pull defaults from the Snakemake object when present, but fall back to NA when
# run standalone (Rscript pdmx_sex.R --input-dir ... --output-csv ...) so the
# argparser interface is genuinely usable for calibration outside the workflow.
.sm <- if (exists("snakemake")) snakemake else NULL
sm_slot <- function(slot, key) {
  if (is.null(.sm)) return(NA)
  val <- methods::slot(.sm, slot)[[key]]
  if (is.null(val)) NA else val
}
.in_matrix <- sm_slot("input", "matrix")
.def_input_dir <- if (is.na(.in_matrix)) NA_character_ else dirname(.in_matrix)

arguments <- arg_parser("Per-barcode sex typing from chrY panel + XIST") %>%
  add_argument("--input-dir",
               help = "Directory holding the filtered 10x matrix (matrix/barcodes/features .tsv.gz)",
               type = "character",
               default = .def_input_dir) %>%
  add_argument("--output-csv",
               help = "Path to save the per-barcode sex_calls.csv",
               type = "character",
               default = sm_slot("output", "sex_calls")) %>%
  add_argument("--capture-id",
               help = "Capture ID for logging and the capture_id column",
               type = "character",
               default = sm_slot("wildcards", "capture")) %>%
  add_argument("--min-umi",
               help = "Cells with < this many UMIs are called 'low_quality' (too shallow to sex-type).",
               type = "numeric",
               default = sm_slot("params", "min_umi")) %>%
  add_argument("--min-genes",
               help = "Cells with < this many detected genes are called 'low_quality'.",
               type = "numeric",
               default = sm_slot("params", "min_genes")) %>%
  add_argument("--chry-min-cp10k",
               help = "chrY panel CP10K at/above which chrY is considered 'present'.",
               type = "numeric",
               default = sm_slot("params", "chry_min_cp10k")) %>%
  add_argument("--xist-min-cp10k",
               help = "XIST CP10K at/above which XIST is considered 'present'.",
               type = "numeric",
               default = sm_slot("params", "xist_min_cp10k")) %>%
  add_argument("--chry-markers",
               help = "Comma-separated chrY-unique gene symbols.",
               type = "character",
               default = sm_slot("params", "chry_markers")) %>%
  add_argument("--xist-gene",
               help = "Gene symbol used as the female (X-inactivation) marker.",
               type = "character",
               default = sm_slot("params", "xist_gene")) %>%
  add_argument("--log-file",
               help = "Path to the log file (defaults to the Snakemake log file).",
               type = "character",
               default = if (is.null(.sm)) NA_character_ else .sm@log[[1]]) %>%
  parse_args()

# --- Fill defaults for any params not supplied (e.g. run standalone) ---
if (is.na(arguments$min_umi))        arguments$min_umi        <- 200
if (is.na(arguments$min_genes))      arguments$min_genes      <- 100
if (is.na(arguments$chry_min_cp10k)) arguments$chry_min_cp10k <- 1.0
if (is.na(arguments$xist_min_cp10k)) arguments$xist_min_cp10k <- 1.0
if (is.na(arguments$chry_markers))   arguments$chry_markers   <- DEFAULT_CHRY_MARKERS
if (is.na(arguments$xist_gene))      arguments$xist_gene      <- DEFAULT_XIST_GENE

# --- Validation ---
if (is.na(arguments$input_dir) || is.na(arguments$output_csv)) {
  stop("Input dir (--input-dir) and output CSV (--output-csv) must be supplied.", call. = FALSE)
}

# --- Logging Setup ---
if (!is.null(arguments$log_file) && !is.na(arguments$log_file)) {
  log_con <- file(arguments$log_file, open = "wt")
  sink(log_con, type = "output")
  sink(log_con, type = "message")
  on.exit({
    sink(type = "output")
    sink(type = "message")
    close(log_con)
  }, add = TRUE)
}

capture_id     <- arguments$capture_id
input_dir      <- arguments$input_dir
output_csv     <- arguments$output_csv
min_umi        <- arguments$min_umi
min_genes      <- arguments$min_genes
chry_min_cp10k <- arguments$chry_min_cp10k
xist_min_cp10k <- arguments$xist_min_cp10k
chry_markers   <- trimws(strsplit(arguments$chry_markers, ",")[[1]])
chry_markers   <- chry_markers[nzchar(chry_markers)]
xist_gene      <- arguments$xist_gene

# Column schema for the per-barcode output (kept identical for the empty case).
SEX_COLS <- c("barcode", "capture_id", "chrY_counts", "chrY_score",
              "xist_counts", "xist_score", "n_umi", "n_genes",
              "sex_score", "sex_call", "confidence")

empty_sex_table <- function() {
  tibble(
    barcode = character(), capture_id = character(),
    chrY_counts = numeric(), chrY_score = numeric(),
    xist_counts = numeric(), xist_score = numeric(),
    n_umi = numeric(), n_genes = integer(),
    sex_score = numeric(), sex_call = character(), confidence = numeric()
  )[, SEX_COLS]
}

# Minimal 10x reader (no Seurat/DropletUtils dependency). Gene symbols are in
# column 2 of features.tsv.gz — exactly the rownames pdmx_filter.R wrote and
# copy_original_features.R restored, so marker lookup is by symbol.
read_10x_dir <- function(dir) {
  mtx_path      <- file.path(dir, "matrix.mtx.gz")
  features_path <- file.path(dir, "features.tsv.gz")
  barcodes_path <- file.path(dir, "barcodes.tsv.gz")
  for (p in c(mtx_path, features_path, barcodes_path)) {
    if (!file.exists(p)) stop(paste("Missing 10x file:", p), call. = FALSE)
  }
  m <- Matrix::readMM(gzfile(mtx_path))
  m <- as(m, "CsparseMatrix")
  features <- read.delim(gzfile(features_path), header = FALSE,
                         stringsAsFactors = FALSE, colClasses = "character")
  barcodes <- readLines(gzfile(barcodes_path))
  # Multi-mode predemux writes a GEX-only matrix but a features.tsv.gz that
  # still lists Antibody Capture rows (column 3 == "Gene Expression" vs others).
  # cellranger lists Gene Expression first and in matrix order, so restricting
  # to those rows realigns features with the matrix. (This rule is gated to
  # count mode, where the counts already match; kept for standalone robustness.)
  if (nrow(features) != nrow(m) && ncol(features) >= 3) {
    ge <- features[[3]] == "Gene Expression"
    if (sum(ge) == nrow(m)) {
      message(sprintf("features(%d) != matrix rows(%d); restricting to %d 'Gene Expression' features.",
                      nrow(features), nrow(m), sum(ge)))
      features <- features[ge, , drop = FALSE]
    }
  }
  if (nrow(m) != nrow(features)) {
    stop(sprintf("features/matrix row mismatch: %d features vs %d matrix rows",
                 nrow(features), nrow(m)), call. = FALSE)
  }
  if (ncol(m) != length(barcodes)) {
    stop(sprintf("barcodes/matrix col mismatch: %d barcodes vs %d matrix cols",
                 length(barcodes), ncol(m)), call. = FALSE)
  }
  # Column 2 = gene symbol; make.unique mirrors Read10X's de-duplication.
  rownames(m) <- make.unique(features[[2]])
  colnames(m) <- barcodes
  m
}

message(sprintf("Starting sex typing for capture: %s", capture_id))
message(sprintf("Input matrix dir: %s", input_dir))
message(sprintf("chrY markers: %s", paste(chry_markers, collapse = ", ")))
message(sprintf("XIST gene: %s", xist_gene))
message(sprintf("Thresholds: min_umi=%s, min_genes=%s, chrY>=%s CP10K, XIST>=%s CP10K",
                min_umi, min_genes, chry_min_cp10k, xist_min_cp10k))

tryCatch({
  counts <- read_10x_dir(input_dir)
  n_cells <- ncol(counts)
  message(sprintf("Loaded matrix: %d genes x %d cells.", nrow(counts), n_cells))

  if (n_cells == 0) {
    message("No cells in filtered matrix. Writing empty sex_calls.csv.")
    write_csv(empty_sex_table(), output_csv)
    message(sprintf("Successfully completed sex typing for capture: %s (0 cells)", capture_id))
  } else {
    # Which markers are actually present (robust to reference changes).
    present_y <- intersect(chry_markers, rownames(counts))
    missing_y <- setdiff(chry_markers, rownames(counts))
    if (length(missing_y) > 0) {
      message(sprintf("WARNING: chrY markers not found and skipped: %s",
                      paste(missing_y, collapse = ", ")))
    }
    if (length(present_y) == 0) {
      message("WARNING: NONE of the chrY markers were found; chrY signal will be 0 for all cells.")
    }
    has_xist <- xist_gene %in% rownames(counts)
    if (!has_xist) {
      message(sprintf("WARNING: %s not found; XIST signal will be 0 for all cells.", xist_gene))
    }

    # Per-cell depth and complexity.
    n_umi_vec   <- Matrix::colSums(counts)
    # Stored non-zeros per column == detected genes (no explicit zeros stored).
    n_genes_vec <- diff(counts@p)

    chrY_counts <- if (length(present_y) > 0) {
      Matrix::colSums(counts[present_y, , drop = FALSE])
    } else {
      rep(0, n_cells)
    }
    xist_counts <- if (has_xist) as.numeric(counts[xist_gene, ]) else rep(0, n_cells)

    # Depth-normalise to counts-per-10k, then log1p for a stable module score.
    size_factor <- pmax(n_umi_vec, 1)
    chrY_cp10k  <- 1e4 * chrY_counts / size_factor
    xist_cp10k  <- 1e4 * xist_counts / size_factor
    chrY_score  <- log1p(chrY_cp10k)
    xist_score  <- log1p(xist_cp10k)
    sex_score   <- chrY_score - xist_score

    # --- Classify ---
    callable  <- (n_umi_vec >= min_umi) & (n_genes_vec >= min_genes)
    male_ev   <- chrY_cp10k >= chry_min_cp10k
    female_ev <- xist_cp10k >= xist_min_cp10k

    sex_call <- rep("ambiguous", n_cells)          # both-present or neither-present
    sex_call[!callable] <- "low_quality"
    sex_call[callable &  male_ev & !female_ev] <- "male"
    sex_call[callable & !male_ev &  female_ev] <- "female"

    confidence <- abs(sex_score)
    confidence[!callable] <- NA_real_

    out <- tibble(
      barcode     = colnames(counts),
      capture_id  = capture_id,
      chrY_counts = as.numeric(chrY_counts),
      chrY_score  = chrY_score,
      xist_counts = as.numeric(xist_counts),
      xist_score  = xist_score,
      n_umi       = as.numeric(n_umi_vec),
      n_genes     = as.integer(n_genes_vec),
      sex_score   = sex_score,
      sex_call    = sex_call,
      confidence  = confidence
    )[, SEX_COLS]

    write_csv(out, output_csv)

    tab <- table(factor(sex_call, levels = c("male", "female", "ambiguous", "low_quality")))
    message(sprintf("Sex calls for %s: male=%d, female=%d, ambiguous=%d, low_quality=%d (of %d cells)",
                    capture_id, tab[["male"]], tab[["female"]], tab[["ambiguous"]],
                    tab[["low_quality"]], n_cells))
    message(sprintf("Saved sex calls to: %s", output_csv))
    message(sprintf("Successfully completed sex typing for capture: %s", capture_id))
  }
}, error = function(e) {
  message(sprintf("Error during sex typing for %s: %s", capture_id, e$message))
  stop(e$message, call. = FALSE)
})
