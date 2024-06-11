#! /bin/bash

set -e
eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    global_profile="--profile profiles/global/nci_a56"
    module load singularity
else
    echo "WARNING: Unknown host: $(hostname)"
    echo "WARNING: No known global profile for this host"
    echo "WARNING: Running without global profile"
    echo "See https://github.com/swarbricklab/snakemake_config/blob/main/README.md"
    global_profile=""
fi

snakemake $global_profile \
    --workflow-profile profiles/workflow \
    --snakefile modules/chromium-preprocessing/workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@
