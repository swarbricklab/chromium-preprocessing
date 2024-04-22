#! /bin/bash

# This script changes the suffix of the barcodes in a bam file
# (Assuming that the current suffix is "-1")
# Warning: this script outputs a binary bam file!
# Redirect the output to file or stream

bam=$1
suffix=$2

pattern="s/(CB:Z:[^\t]+)-1/\1-$suffix/g"

samtools view -h $bam | sed -E $pattern | samtools view -bS -
