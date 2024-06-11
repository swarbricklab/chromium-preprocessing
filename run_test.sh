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
    --workflow-profile profiles/workflow/ \
    --snakefile workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@

find results -type f -exec md5sum {} \; \
    | sed "s/  /,/g" \
    | csvsort -c 2 -H \
    | grep -v "/_" \
    | grep -v "/\." \
    | grep -v "mri" \
    | grep -v "web_summary.html" \
    > test_data/observed.csv

if diff test_data/expected.csv test_data/observed.csv; then
    echo "Observed results match expected results. Test passed"
    exit 0
else
    echo "Observed results do not match expected results. Has the workflow changed?"
    echo "Compare expected (<) to observed (>)"
    exit 1
fi
