from snakemake.io import expand
import pandas as pd

# Determine which assays are present in libraries.csv
def find_assays(library_path):
    libraries=pd.read_csv(library_path)
    assays=libraries['feature_types'].unique()
    mapping = {
        "Gene Expression": "gene-expression",
        "VDJ-T": "vdj",
        "Antibody Capture": "feature"
    }
    for assay in assays:
        if assay not in mapping.keys():
            print("Unexpected assay (feature_type) in libraries.csv: {}".format(assay))
            exit()
    return [mapping.get(assay, assay) for assay in assays]

# # Get list of final targets
# def final_targets(wildcards):
#     targets = []
#     # cellranger count
#     if 'count' in config["params"]:
#         count_targets = expand(count_dir/"{capture}/outs/molecule_info.h5", capture = captures.index)
#         targets.extend(count_targets)
#         targets.append(count_dir/"cr_summary.csv")
#     # cellranger aggr
#     if 'aggr' in config["params"]:
#         aggr_targets = aggr_all(wildcards)
#         targets.extend(aggr_targets)
#     print("Final targets: ")
#     for target in targets:
#         print("  -", target)
#     return targets

# Get fastq paths for capture of interest from libraries.csv
# Used in rule cellranger_count
def get_fastqs(wildcards):
    libraries=pd.read_csv(config['deps']['libraries'])
    capture_subset=libraries[libraries['fastq_id'] == wildcards.capture]
    return capture_subset['fastqs'].tolist()

# Translate gene-expression options in config to a string that can be passed to 'cellranger count'
# Used in rule cellranger_count
def get_count_options(wildcards):
    options=""
    # Here 'flags' are parameters that did not take a value
    flags=["no-secondary"]
    for parameter,value in config["params"]["gene-expression"].items():
        if parameter in flags:
            if value == "true":
                options=options+" --"+parameter
            else:
                pass
        else:
            options=options+" --"+parameter+" "+value
    return options

# Get the capture_ids associated with a specific aggr_id group 
def get_cellranger_aggr_aggr_captures_input(wildcards):

    wanted_input = []

    df_samples = pd.read_csv(config["params"]["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

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

    if config["params"]["aggr"]["activate"]:
        # parse sample-sheet
        df_sample_sheet = pd.read_csv(config["params"]["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

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
    df_samples = pd.read_csv(config["params"]["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})
    capture_ids = df_samples.loc[df_samples["aggr_id"] == wildcards.aggr_id, ["capture_id"]]
    capture_ids = list(set(capture_ids["capture_id"].tolist()))
    source_bams = expand(
        [count_dir/"{capture}/outs/possorted_genome_bam.bam"],
        capture=capture_ids
    )
    return source_bams