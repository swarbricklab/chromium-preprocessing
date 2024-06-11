#! /bin/bash

# This script wraps cellranger aggr
# As well as the parameters for the `cellranger aggr` command itself,
# the wrapper is also aware of the intended output destination and log file location

# TMPDIR (on local disk) is used for the work directory 
# and results are copied to the specified output directory
# This script also removes SC_RNA_AGGREGATOR_CS (intermediate files) before returning results

set -e
project_top=$PWD

# Read parameters and calculate paths

#log=$project_top/${snakemake_log[0]}
log=$project_top/${snakemake_log[0]}
out_dir=$project_top/${snakemake_output[0]}
out_parent=$(dirname $out_dir)
#capture=${snakemake_wildcards[capture]}
aggr_id=${snakemake_wildcards[aggr_id]}
aggr_csv=$project_top/${snakemake_input[aggr_csv]}
#fastqs=$project_top/${snakemake_input[fastqs]}
#transcriptome=$project_top/${snakemake_params[transcriptome]}
cores=${snakemake_resources[threads]}
mem=${snakemake_resources[mem_gb]}
flags=${snakemake_params[flags]}

# Debug messages
echo "Aggregating aggr_id: $aggr_id" 
echo "Output parent: $out_parent" 
echo "File defining capture ids in aggr_id: $aggr_csv" 
echo "Log: $log" 
echo "Cores: $cores"
echo "Memory: $mem"

# Switch to local disk for faster disk I/O
cd ${snakemake_resources[tmpdir]}
echo "Work directory: $PWD"

# Copy any leftover intermediate files from a previously interrupted pipestance
if [ -e $out_parent/$aggr_id ]; then
    rsync -ah --progress $out_parent/$aggr_id/* .
fi

# Run cellranger, saving cellranger-specific logs
cmd="cellranger aggr \
    --id=$aggr_id \
    --csv=$aggr_csv \
    --normalize=mapped \
    --jobmode=local \
    --localcores=$cores \
    --localmem=$mem \
    $flags"

touch $log 
echo $cmd > $log

if eval $cmd >> $log; then
    echo "Cellranger has completed" >> $log 
    # Remove temporary files
    # TODO: set as temp output dir in rule?
    rm -rf **/SC_RNA_AGGREGATOR_CS
    # Make compression consistent
    # By default gzip includes timestamp information, 
    # and so the same data will produce a different hash when run at different times
    # Unzipping and rezipping with '--no-name' removes timestamp information
    compressed_files="features.tsv barcodes.tsv matrix.mtx"
    for file in $compressed_files; do
        dir=$aggr_id/outs/count/filtered_feature_bc_matrix
        echo "Recompressing $dir/$file.gz" >> $log 
        gunzip $dir/$file.gz
        gzip --no-name $dir/$file
    done
    # Return results
    rsync -ah --progress $aggr_id $out_parent >> $log
else
    echo "Cellranger has failed" >> $log 
    rsync -ah --progress $aggr_id $out_parent >> $log  
fi
cd -