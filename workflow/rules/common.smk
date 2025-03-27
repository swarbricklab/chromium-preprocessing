from snakemake.io import expand
import pandas as pd

# Get list of final targets
def final_targets(wildcards):
    targets = []
    # cellranger count
    if 'count' in config:
        count_targets = expand(count_dir/"{capture}/outs/molecule_info.h5", capture = captures.index)
        targets.extend(count_targets)
        targets.append(count_dir/"cr_summary.csv")
    # cellranger aggr
    if 'aggr' in config:
        aggr_targets = aggr_all(wildcards)
        targets.extend(aggr_targets)
    print("Final targets: ")
    for target in targets:
        print("  -", target)
    return targets

# Look up field in sample_sheet
def capturesheet(field):
    def handle_wildcards(wildcards):
        result=captures.loc[wildcards.capture, field]
        return result.split(";")
    return handle_wildcards

# Get the capture_ids associated with a specific aggr_id group 
def get_cellranger_aggr_aggr_captures_input(wildcards):

    wanted_input = []

    df_samples = pd.read_csv(config["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

    capture_ids = df_samples.loc[df_samples["aggr_id"] == wildcards.aggr_id, ["capture_id"]]
    capture_ids = list(set(capture_ids["capture_id"].tolist()))

    wanted_input.extend(
        expand([
           count_dir/"{capture_id}/outs/molecule_info.h5"
        ],
            capture_id=capture_ids
        )
    )

    return wanted_input

# get rule all input files for cellranger aggr
def aggr_all(wildcards):

    aggr_input = []

    if config["aggr"]["activate"]:
        # parse sample-sheet
        df_sample_sheet = pd.read_csv(config["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

        aggr_ids = list(set(df_sample_sheet["aggr_id"].tolist()))

        if "NONE" in aggr_ids:
            aggr_ids.remove("NONE")
        
        aggr_input.extend(
            expand([
                aggr_dir/"csvs/{aggr_id}.csv",
                aggr_dir/"output/{aggr_id}/outs/count/summary.json",
                aggr_dir/"bams/{aggr_id}/merged.bam"
            ],
                aggr_id=aggr_ids
            )
        )

    return aggr_input

# Returns individual source bam files to be merged as part of aggr
def get_source_bams(wildcards):
    df_samples = pd.read_csv(config["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})
    capture_ids = df_samples.loc[df_samples["aggr_id"] == wildcards.aggr_id, ["capture_id"]]
    capture_ids = list(set(capture_ids["capture_id"].tolist()))
    source_bams = expand(
        [count_dir/"{capture}/outs/possorted_genome_bam.bam"],
        capture=capture_ids
    )
    return source_bams