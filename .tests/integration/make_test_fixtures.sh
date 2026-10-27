#!/bin/bash
#
# Regenerate the bundled tiny test fixtures from public 10x Genomics data.
#
# The fixtures under .tests/integration/data/ are DERIVED (deterministically downsampled) from public,
# de-identified 10x Genomics healthy-donor PBMC datasets. They are DVC-tracked for
# convenience, but this script is the authoritative provenance: it reproduces them
# byte-for-byte from the public source tarballs. No private/patient data is involved.
#
# Public sources (10x public data-use terms; research use):
#   count mode (3' GEX)         : pbmc_1k_v3
#     https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_v3/pbmc_1k_v3_fastqs.tar
#   multi mode (5' GEX+FB+VDJ)  : vdj_v1_hs_pbmc2
#     https://cf.10xgenomics.com/samples/cell-vdj/3.0.0/vdj_v1_hs_pbmc2_5gex_protein/vdj_v1_hs_pbmc2_5gex_protein_fastqs.tar
#     https://cf.10xgenomics.com/samples/cell-vdj/3.0.0/vdj_v1_hs_pbmc2_t/vdj_v1_hs_pbmc2_t_fastqs.tar
#   antibody feature reference  : vdj_v1_hs_pbmc2_5gex_protein_feature_ref.csv
#     (committed verbatim as config/feature_barcode_reference.csv)
#
# Downsampling: deterministic stride sampling. Keep source record i iff i % STRIDE == 0;
# assign the k-th kept record (k = i/STRIDE) to capture partition k % NPARTS. The predicate
# depends only on the record index, so R1/R2/I1 stay perfectly in sync. Lanes are
# concatenated in sorted order to give a stable global record index. One awk pass per
# (library, read type) fans out to all capture partitions at once. Pure zcat/awk/gzip.
#
# The STRIDE values below reproduce the committed fixtures (~3.1M read pairs/capture for the
# count GEX; ~3.0M / ~1.5M / ~1.5M reads/capture for multi GEX / Antibody / VDJ-T). They are
# "downsampled a lot but not so far that Cell Ranger or the downstream QC steps break".
#
# Usage:  .tests/integration/make_test_fixtures.sh <workdir_with_extracted_fastqs>
# where <workdir> contains the extracted source dirs:
#   pbmc_1k_v3_fastqs/
#   vdj_v1_hs_pbmc2_5gex_protein_fastqs/{vdj_v1_hs_pbmc2_5gex_fastqs,vdj_v1_hs_pbmc2_antibody_fastqs}/
#   vdj_v1_hs_pbmc2_t_fastqs/
set -euo pipefail

SRC="${1:?usage: make_test_fixtures.sh <workdir_with_extracted_source_fastqs>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ds_lib OUTDIR CAP_BASE "CAP_SUFFIXES" SUBDIR STRIDE NPARTS SRCDIR SRCPREFIX
# Writes OUTDIR/<CAP>/[SUBDIR/]<CAP>_S1_L001_<RT>_001.fastq.gz for each capture partition.
ds_lib() {
  local OUTDIR="$1" CAPS_STR="$2" SUB="$3" STRIDE="$4" NPARTS="$5" SRCDIR="$6" PREF="$7"
  local -a CAPS=($CAPS_STR)
  local sep=""; [ -n "$SUB" ] && sep="/"
  local c; for c in "${CAPS[@]}"; do mkdir -p "$OUTDIR/$c$sep$SUB"; done
  local rt lanes op i
  for rt in R1 R2 I1; do
    lanes=( $(ls "$SRCDIR"/${PREF}_S*_L*_${rt}_001.fastq.gz 2>/dev/null | sort) )
    [ ${#lanes[@]} -eq 0 ] && { echo "ERROR: no $rt lanes for $PREF in $SRCDIR" >&2; exit 2; }
    op=""
    for i in "${!CAPS[@]}"; do [ -n "$op" ] && op="$op:"; op="$op$OUTDIR/${CAPS[$i]}$sep$SUB/${CAPS[$i]}_S1_L001_${rt}_001.fastq.gz"; done
    echo "  $SUB${SUB:+/}$rt  stride=$STRIDE  parts=$NPARTS  lanes=${#lanes[@]}"
    zcat "${lanes[@]}" | awk -v S="$STRIDE" -v P="$NPARTS" -v OP="$op" '
      BEGIN{ n=split(OP,a,":"); for(i=1;i<=n;i++) cmd[i-1]="gzip > \"" a[i] "\"" }
      { r=int((NR-1)/4); if(r%S==0){ print | cmd[int(r/S)%P] } }
      END{ for(i=0;i<P;i++) close(cmd[i]) }'
  done
}

echo "== count fixture: tiny_pbmc (pbmc_1k_v3, 3 GEX captures) =="
rm -rf "$REPO/test/data/tiny_pbmc"
ds_lib "$REPO/test/data/tiny_pbmc/GE" "PBMC_001 PBMC_002 PBMC_003" "" 7 3 \
  "$SRC/pbmc_1k_v3_fastqs" pbmc_1k_v3

echo "== multi fixture: tiny_pbmc2 (vdj_v1_hs_pbmc2, 2 captures x GEX/Antibody/VDJ-T) =="
rm -rf "$REPO/test/data/tiny_pbmc2"
ds_lib "$REPO/test/data/tiny_pbmc2" "PBMC2_a PBMC2_b" GE5   75 2 \
  "$SRC/vdj_v1_hs_pbmc2_5gex_protein_fastqs/vdj_v1_hs_pbmc2_5gex_fastqs"     vdj_v1_hs_pbmc2_5gex
ds_lib "$REPO/test/data/tiny_pbmc2" "PBMC2_a PBMC2_b" FB-AB 45 2 \
  "$SRC/vdj_v1_hs_pbmc2_5gex_protein_fastqs/vdj_v1_hs_pbmc2_antibody_fastqs" vdj_v1_hs_pbmc2_antibody
ds_lib "$REPO/test/data/tiny_pbmc2" "PBMC2_a PBMC2_b" VDJ-T 11 2 \
  "$SRC/vdj_v1_hs_pbmc2_t_fastqs"                                            vdj_v1_hs_pbmc2_t

echo "Done. Fixtures written under $REPO/test/data/{tiny_pbmc,tiny_pbmc2}."
