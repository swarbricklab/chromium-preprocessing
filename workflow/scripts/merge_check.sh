#! /bin/bash

# This script is a sanity check that bam merger has worked as expected

merged_bam=$1    # merged bam file produced by merge_bams rule and merge_bams.sh script
declare -a source
source[1]=$2       # path to cellranger outs for first source
source[2]=$3       # path to cellranger outs for second source

module load johree/samtools/0.1.19--h270b39a_9 > /dev/null 2>&1 

### Function definitions

# This function counts reads containing cell barcodes in the give bam file
function count_barcodes() {
    samtools view -h $1 | grep "CB:Z" | pv | wc -l
}

# This function extracts the unique barcodes within the merged bam file,
# filtering for barcodes that end with the given suffix (1 or 2)
function extract_barcodes() {
    # 1. Convert binary bam to text sam format
    # 2. Filter for only lines containing "CB:Z" (cell barcode) tag
    # 3. Extract only the cell barcode (a sequence of 16 A,C,G or T followed by -1 or -2)
    # 4. Filter for only barcodes with the suffix of interest
    # 5. Sort and filter for only unique barcodes
    samtools view -h $merged_bam \
    | pv \
    | grep "CB:Z"  \
    | sed -E 's/^.*CB\:Z\:([ACGT]{16}-[12]).*$/\1/g' \
    | grep $1 \
    | sort | uniq
}

# This function unzips the raw barcodes.tsv.gz files from cellranger for the given source (1 or 2)
function unzip_cellranger_barcodes() {
    zcat ${source[$1]}/raw_feature_bc_matrix/barcodes.tsv.gz \
    | sed "s/-1/-$1/g" \
    | sort
}

# This function compares barcodes from the merged bam against barcodes from cellranger 
# for the given source (1 or 2)
function compare_barcodes() {
    if diff <(unzip_cellranger_barcodes $1) <(extract_barcodes $1) > /dev/null 2>&1 ; then
        echo "Source$1: Barcodes in merged bam match barcodes in cellranger outs"
    else
        echo "Source$1: Barcodes in marged bam do not match barcodes in cellranger outs"
    fi 
}

### Main

# Count barcodes for each bam
count1=$(count_barcodes ${source[1]}/possorted_genome_bam.bam)
count2=$(count_barcodes ${source[2]}/possorted_genome_bam.bam)
count_total=$(( $count1 + $count2 ))
count_merged=$(count_barcodes $merged_bam)

# Report barcode counts
echo
echo "Reads containing barcodes"
echo "Source1:           $count1"
echo "Source2:           $count2"
echo "Source1 + Source2: $count_total"
echo "Merged bam:        $count_merged"

# Compare barcodes in merged bam with raw barcodes.tsv.gz files from cellranger
compare_barcodes 1
compare_barcodes 2