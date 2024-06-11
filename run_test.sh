#! /bin/bash

set -e

eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    profile=nci_a56
    module load singularity
elif [[ "$(hostname)" == *"dice"* || "$(hostname)" == *"brenner"* ]]; then
    echo "Running on Garvan HPC"
    profile=drmaa
else
    echo "Unknown host: defaulting to drmaa profile"
    echo "Review workflow/profiles/drmaa for appropriateness to your platform"
    profile=drmaa
fi

mkdir -p logs/chromium-preprocessing/joblogs

snakemake \
    --profile /g/data/a56/config/snakemake/nci_a56 \
    --workflow-profile workflow/profiles/pbspro \
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
