#! /bin/bash

set -e

snakemake --profile workflow/profiles/drmaa \
    --snakefile workflow/Snakefile \
    --configfile config/chromium-preprocessing/config.yaml \
    $@

find results -type f -exec md5sum {} \; \
    | sed "s/  /,/g" \
    | csvsort -c 2 -H \
    | grep -v "/_" \
    | grep -v "/\." \
    | grep -v "mri" \
    > test_data/observed.csv

diff test_data/expected.csv test_data/observed.csv