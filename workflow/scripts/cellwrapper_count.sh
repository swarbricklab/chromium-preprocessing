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
# Construct comma-separated list of fastq directories
fastqs=""
for dir in ${snakemake_input[fastqs]}; do 
    fastqs=$project_top/$dir,$fastqs
done
fastqs=${fastqs%,} # strip trailing comma if present
transcriptome=$project_top/${snakemake_params[transcriptome]}
cores=${snakemake_resources[threads]}
mem=${snakemake_resources[mem]%%GB}
flags=${snakemake_params[flags]}

# Debug messages
cat >> $log <<EOF
Processing sample: $sample 
Output parent: $out_parent 
Log: $log 
Resources ${snakemake_resources}
Fastq path: $fastqs
Transcriptome: $transcriptome
Cores: $cores
Memory: $mem
EOF

# Switch to local disk for faster disk I/O
cd ${snakemake_resources[tmpdir]}
echo "Work directory: $PWD"
# Copy any leftover intermediate files from a previously interrupted pipestance
if [ -d $out_parent/$capture ]; then
    echo "Copying leftover intermediate files"
    cmd="rsync -ah --progress $out_parent/$capture/* ."
    echo $cmd; eval $cmd
    echo "Finished copying"
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
echo "cellranger will be run with the following options"
echo $cmd

touch $log 
echo $cmd >  $log
if eval $cmd >> $log; then
    echo "Cellranger has completed" >> $log 
    # Remove temporary files
    rm -rf **/SC_RNA_COUNTER_CS
    # Make compression consistent
    compressed_files="features.tsv barcodes.tsv matrix.mtx"
    fc_barcode_dirs="filtered_feature_bc_matrix raw_feature_bc_matrix"
    for mat_dir in $fc_barcode_dirs; do
        for file in $compressed_files; do
            dir=$capture/outs/$mat_dir 
            gunzip $dir/$file.gz
            gzip --no-name $dir/$file
        done
    done
    # Log bam checksum
    md5sum $capture/outs/possorted_genome_bam.bam >> $log
    # Return results
    rsync -ah $capture $out_parent >> $log
else
    echo "Cellranger has failed" >> $log 
    rsync -ah --progress $capture $out_parent >> $log  
    exit 1
fi
cd -