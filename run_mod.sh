#! /bin/bash

snakemake --profile modules/chromium-preprocessing/config/profiles/drmaa \
    --snakefile modules/chromium-preprocessing/workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@
