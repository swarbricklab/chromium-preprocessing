#! /bin/bash

snakemake --profile config/profiles/drmaa \
    --snakefile workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@
