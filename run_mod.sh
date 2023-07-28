#! /bin/bash

set -e

snakemake --profile config/chromium-preprocessing/profiles/drmaa \
    --snakefile modules/chromium-preprocessing/workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@

dt_snapshot_outs config/chromium-preprocessing/pep_config.yaml
