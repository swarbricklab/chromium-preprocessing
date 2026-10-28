#! /bin/bash
#
# Run the bundled count + multi tests and verify the results against the golden
# (.tests/integration/results, DVC-tracked).
#
# A real run stashes the committed golden, re-runs the workflow from scratch, then
# content-compares the fresh output against the golden with
# workflow/scripts/compare_to_golden.py (Cell Ranger output is not bit-reproducible,
# so viewer files / HTML / BAMs are compared for presence only — see that script and
# issue #137). The script exits non-zero if any meaningful output differs.
#
# Usage:
#   ./run_test.sh                 # run both tests and compare to the golden
#   ./run_test.sh --update-golden # run, compare, but KEEP the fresh output so you
#                                  #   can `dvc add .tests/integration/results` to bless a new golden
#   ./run_test.sh -n              # dry-run (passthrough; no stash/compare)
#   ./run_test.sh --unlock        # passthrough to snakemake
#
# Assumes: test data pulled (dvc pull -R .tests/integration/data/), the golden materialised
# (dvc checkout .tests/integration/results.dvc), and a conda env `snakemake_7.32.4`.

set -euo pipefail

eval "$(conda shell.bash hook)"
conda activate snakemake_7.32.4

export WORKFLOW_ROOT="."

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
    workflow_profile=""
fi

tests="count multi"
export JOBMODE="'profiles/global/nci/resources/pbspro.template'"

# Pin report timestamps so our HTML reports are byte-identical across runs and can be
# compared against the golden (reproducible-builds convention; see
# workflow/scripts/cellranger_summary_utils.py:report_timestamp). The golden was
# generated with this same value. 1704067200 = 2024-01-01T00:00:00Z.
export SOURCE_DATE_EPOCH=1704067200

run_snakemake() {
    local cfg="$1"; shift
    snakemake $global_profile $workflow_profile \
        --snakefile Snakefile \
        --configfile "$cfg" \
        "$@"
}

# --- passthrough modes: dry-run / unlock / graph -> no golden stash or compare ---
for a in "$@"; do
    case "$a" in
        -n|--dry-run|-np|--unlock|--dag|--rulegraph|--filegraph)
            for test in $tests; do run_snakemake "config/tests/$test/config.yaml" "$@"; done
            exit 0
            ;;
    esac
done

# --- real run: separate --update-golden from the snakemake args ---
update_golden=false
sm_args=()
for a in "$@"; do
    if [[ "$a" == "--update-golden" ]]; then update_golden=true; else sm_args+=("$a"); fi
done

golden_ref=".tests/integration/.golden_ref"
golden_stashed=false

# Restore the committed golden on exit unless we're deliberately updating it.
cleanup() {
    if [[ "$golden_stashed" == true && "$update_golden" != true ]]; then
        rm -rf .tests/integration/results
        mv "$golden_ref" .tests/integration/results 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Stash the golden so the fresh run can be compared against it.
if [[ -d .tests/integration/results ]]; then
    rm -rf "$golden_ref"
    mv .tests/integration/results "$golden_ref"
    golden_stashed=true
else
    echo "WARNING: .tests/integration/results (golden) not materialised — running without comparison."
    echo "         Fetch it first: dvc checkout .tests/integration/results.dvc"
fi

# Run the workflow (recreates .tests/integration/results).
for test in $tests; do
    run_snakemake "config/tests/$test/config.yaml" "${sm_args[@]+"${sm_args[@]}"}"
done

# Compare each mode against the golden.
status=0
if [[ "$golden_stashed" == true ]]; then
    echo "=================== comparing results to golden ==================="
    for test in $tests; do
        if ! python workflow/scripts/compare_to_golden.py \
                ".tests/integration/results/cellranger/${test}_test" \
                "$golden_ref/cellranger/${test}_test" --label "$test"; then
            status=1
        fi
    done
    if [[ "$update_golden" == true ]]; then
        echo "--update-golden: keeping the fresh output. To bless it: dvc add .tests/integration/results && dvc push"
        rm -rf "$golden_ref"
        golden_stashed=false
    elif [[ "$status" -eq 0 ]]; then
        echo "All tests match the golden."
    else
        echo "RESULT MISMATCH: fresh output differs from the golden (see above)."
        echo "If the change is intended, re-run with --update-golden, then dvc add/push."
    fi
fi

exit $status
