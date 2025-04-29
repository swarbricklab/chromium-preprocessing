#! /bin/bash

set -e
eval  "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

export JOBMODE="'modules/chromium-preprocessing/profiles/global/nci/resources/pbspro.template'"

module="chromium-preprocessing"

if [[ "$(hostname)" == *"nci"* ]]; then
    echo "Running on NCI"
    global_profile="--profile modules/${module}/profiles/global/nci"
    workflow_profile="--workflow-profile modules/${module}/profiles/workflow "
    module load singularity
    mkdir -p logs/joblogs
else
    echo "WARNING: Unknown host: $(hostname)"
    echo "WARNING: No known global profile for this host"
    echo "WARNING: Running without global profile"
    echo "See https://github.com/swarbricklab/snakemake_config/blob/main/README.md"
    global_profile=""
fi

# Make rule graph
graph_dir=docs/graphs
mkdir -p $graph_dir
snakemake $global_profile $workflow_profile \
    --snakefile modules/${module}/Snakefile \
    --configfile config/${module}/config.yaml \
    --rulegraph \
    | dot -Tsvg \
    > ${graph_dir}/${module}.svg

# Run workflow
snakemake $global_profile $workflow_profile \
    --snakefile modules/${module}/Snakefile \
    --configfile config/${module}/config.yaml \
    --keep-incomplete \
    $@
