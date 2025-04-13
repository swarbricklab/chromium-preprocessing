#! /bin/bash

set -e

eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    global_profile="--profile profiles/global/nci"
    workflow_profile="--workflow-profile profiles/workflow"
    module load singularity
    mkdir -p logs/joblogs
else
    echo "WARNING: Unknown host: $(hostname)"
    echo "WARNING: No known global profile for this host"
    echo "WARNING: Running without global profile"
    echo "See https://github.com/swarbricklab/snakemake_config/blob/main/README.md"
    global_profile=""
fi

tests="count multi"

export JOBMODE="'profiles/global/nci/resources/pbspro.template'"

for test in $tests; do
    snakemake $global_profile $workflow_profile \
        --snakefile Snakefile \
        --configfile config/tests/$test/config.yaml \
        $@
done
