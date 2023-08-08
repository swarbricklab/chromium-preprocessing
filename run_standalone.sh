#! /bin/bash

snakemake --profile workflow/profiles/drmaa \
    --snakefile workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@
