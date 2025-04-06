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

# Get fastq paths for capture of interest from libraries.csv
# Used in rule cellranger_count
def get_fastqs(wildcards):
    libraries=pd.read_csv(config['deps']['libraries'])
    capture_subset=libraries[libraries['fastq_id'] == wildcards.capture]
    return capture_subset['fastqs'].tolist()

# Translate aggr options in config to a string that can be passed to 'cellranger aggr/count'
# Used in rules cellrange_count and cellranger_aggr
def get_options(section):
    def handle_wildcards(wildcards):
        options=""
        # Here 'flags' are parameters that did not take a value
        flags=["no-secondary"]
        # The rename map translates parameters that have different names in multi config versus count/aggr CLI
        rename_map={ 'no-secondary': 'nosecondary'}
        for parameter,value in config["params"][section].items():
            if parameter in flags:
                # Only add to option string if true
                if value == "true":
                    # Rename if necessary
                    if parameter in rename_map.keys():
                        parameter = rename_map['parameter']
                    options=options+" --"+parameter
                else:
                    pass
            else:
                options=options+" --"+parameter+" "+value
        return options
    return handle_wildcards

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