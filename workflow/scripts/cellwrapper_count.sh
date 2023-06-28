#! /bin/bash

# This script wraps cellranger count
# As well as the parameters for the `cellranger count` command itself,
# the wrapper is also aware of the intended output destination and log file location

# TMPDIR (on local disk) is used for the work directory 
# and results are copied to the specified output directory
# This script also removes SC_RNA_COUNTER_CS (intermediate files) before returning results

set -e
project_top=$PWD

# Read parameters and calculate paths

log=$project_top/${snakemake_log[0]}
out_dir=$project_top/${snakemake_output[0]}
out_parent=$(dirname $out_dir)
capture=${snakemake_wildcards[capture]}
fastqs=$project_top/${snakemake_input[fastqs]}
transcriptome=$project_top/${snakemake_params[transcriptome]}
cores=${snakemake_resources[cores]}
mem=${snakemake_resources[mem]%GB}
flags=${snakemake_params[flags]}

# Debug messages

echo "Processing sample: $capture" 
echo "Output parent: $out_parent" 
echo "Log: $log" 
echo "Fastq path: $fastqs"
echo "Transcriptome: $transcriptome"
echo "Cores: $cores"
echo "Memory: $mem"

# Switch to local disk for faster disk I/O
cd ${snakemake_resources[tmpdir]}
echo "Work directory: $PWD"
# Copy any leftover intermediate files from a previously interrupted pipestance
if [ -e $out_parent/$capture ]; then
    rsync -ah --progress $out_parent/$capture/* .
fi
# Run cellranger, saving cellranger-specific logs
cmd="cellranger count \
    --id=$capture \
    --sample=$capture \
    --fastqs=$fastqs \
    --transcriptome=$transcriptome \
    --jobmode=local \
    --localcores=$cores \
    --localmem=$mem \
    $flags"

touch $log 
echo $cmd >  $log
if eval $cmd >> $log; then
    echo "Cellranger has completed" >> $log 
    # Remove temporary files
    rm -rf **/SC_RNA_COUNTER_CS
    # Return results
    rsync -ah --progress $capture $out_parent >> $log
else
    echo "Cellranger has failed" >> $log 
    rsync -ah --progress $capture $out_parent >> $log  
fi
cd -