#! /bin/bash

# Prepare the chromium-preprocessing reference data.
#
# The 10x Genomics references are tracked publicly via `dvc import-url` (see the
# README and resources/**/*.tar.gz.dvc) straight from 10x's own download URLs, so
# they can be fetched without access to any private registry. This script unpacks
# the downloaded tarballs into the directory paths the workflow config / rules
# expect. Run it, after fetching the tarballs, from the top of the repo
# (standalone) or of the super-project that mounts this workflow as a module --
# the same place you run run_mod.sh / run_test.sh.
#
#   resources/transcriptomes/refdata-gex-GRCh38-2020-A.tar.gz  (~11 GB) ->
#       resources/transcriptomes/refdata-gex-GRCh38-2020-A/      (Cell Ranger GEX ref)
#   resources/vdj/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0.tar.gz ->
#       resources/vdj/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0/   (VDJ ref)
#
# The 10x references are redistributed by 10x under their own license; `dvc update`
# re-fetches them directly from 10x, so each user obtains them from the source.
#
# Usage:
#   dvc pull                 # if you have the project's (private) DVC remote, OR
#   dvc update resources/transcriptomes/*.tar.gz.dvc resources/vdj/*.tar.gz.dvc
#                            #   to re-fetch the tarballs directly from 10x
#   ./prep.sh                # unpack the tarballs into place
#
# Options:
#   --force   re-unpack even if the output directory already looks complete.

set -euo pipefail

force="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)   force="true"; shift ;;
        -h|--help) sed -n '3,30p' "$0" | cut -c 3-; exit 0 ;;
        *)         echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

# tarball -> parent dir to extract into -> sentinel file that marks a complete unpack
unpack() {
    local tarball="$1" dest_parent="$2" sentinel="$3"
    if [[ "$force" != "true" && -e "$sentinel" ]]; then
        echo "  already unpacked: $sentinel (use --force to redo)"
        return 0
    fi
    [[ -f "$tarball" ]] || die "missing $tarball -- fetch it first (dvc pull / dvc update)"
    echo "  unpacking $tarball -> $dest_parent/"
    mkdir -p "$dest_parent"
    tar xzf "$tarball" -C "$dest_parent"
    [[ -e "$sentinel" ]] || die "unpack did not produce $sentinel"
}

echo "Preparing chromium-preprocessing references..."
unpack resources/transcriptomes/refdata-gex-GRCh38-2020-A.tar.gz \
       resources/transcriptomes \
       resources/transcriptomes/refdata-gex-GRCh38-2020-A/reference.json
unpack resources/vdj/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0.tar.gz \
       resources/vdj \
       resources/vdj/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0/reference.json
echo "Done."
