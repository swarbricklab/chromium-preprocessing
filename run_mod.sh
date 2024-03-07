#! /bin/bash

set -e

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    profile=pbspro
elif [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on Garvan HPC"
    profile=drmaa
else
    echo "Unknown host: defaulting to drmaa profile"
    echo "Review workflow/profiles/drmaa for appropriateness to your platform"
    profile=drmaa
fi

snakemake --profile modules/chromium-preprocessing/workflow/profiles/$profile \
    --snakefile modules/chromium-preprocessing/workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@

dt_snapshot_outs config/chromium-preprocessing/pep_config.yaml
