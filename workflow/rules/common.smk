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

# Return h5 files for given pool
def get_h5_in_pool(wildcards):
    capture_list = captures[captures['pool'] == wildcards.pool].index.tolist()
    return expand(out_dir/"h5/{capture}/molecule_info.h5",capture=capture_list)

# get rule all input files for cellranger aggr
def aggr_all():
    pool_list = captures.loc[
        captures['pool'] != captures.index, 'pool'
    ].unique().tolist()
        
    return expand(
        [   
            out_dir/"aggr/{pool}/outs/count/summary.json",
            out_dir/"bams/{pool}/merged.bam.bai"
        ],
        pool=pool_list
    )

# Returns individual source bam files to be merged as part of aggr
def get_source_bams(wildcards):
    capture_list = captures[captures["pool"] == wildcards.pool].index.tolist()
    source_bams = expand(
        out_dir/"bam/count/{capture}/assigned_alignments.bam",
        capture=capture_list
    )
    return source_bams
