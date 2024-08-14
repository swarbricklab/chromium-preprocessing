#! /bin/bash

# This script merges the bam files that share a common "aggr_id" in the aggr sample sheet
# The input bam files are first "resuffixed" so that the barcodes in the merged bam will be unique

source_bams=${snakemake_input[source_bams]}
aggr_id=${snakemake_wildcards[aggr_id]}
sample_sheet=${snakemake_params[sample_sheet]}
out_bam=${snakemake_output[0]}
out_dir=$(dirname $out_bam)
log=${snakemake_log[0]}

exec > $log 2>&1
set -x

echo "Work directory: $PWD"
export PATH=../scripts/:$PATH

sample_number=1 # loop counter
temp_files=() # Array to hold names of temporary files

# Loop over the samples with the specifed aggr_id, building the merge command \
for bam in $source_bams; do
    temp_bam="$out_dir/temp_${sample_number}.bam"
    if [ "$sample_number" -eq "1" ]; then
        # no need to resuffix
        cp $bam $temp_bam
    else
        resuffix_bam.sh $bam $sample_number > $temp_bam
    fi
    temp_files+=("$temp_bam")
    ((sample_number++))
done 

merge_command="samtools merge $out_bam ${temp_files[*]}"
echo $merge_command >&2
eval $merge_command

# Clean up temporary files
rm -f "${temp_files[@]}"
