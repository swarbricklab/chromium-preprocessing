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

snakemake --profile workflow/profiles/$profile \
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

diff test_data/expected.csv test_data/observed.csv
