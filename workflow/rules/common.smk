from snakemake.io import expand
import pandas as pd
import itertools

# Determine which assays are present in libraries.csv
def find_assays(libraries):
    assays=libraries['feature_types'].unique()
    mapping = {
        "Gene Expression": "gene-expression",
        "VDJ-B": "vdj",
        "VDJ-T": "vdj",
        "Antibody Capture": "feature"
    }
    for assay in assays:
        if assay not in mapping.keys():
            print("Unexpected assay (feature_type) in libraries.csv: {}".format(assay))
            exit()
    return [mapping.get(assay, assay) for assay in assays]

# Determine which supported VDJ assays are present (VDJ-T or VDJ-B)
def find_vdj_assays(libraries):
    supported_vdj_assays = {
        'VDJ-T': 'vdj_t',
        'VDJ-B': 'vdj_b'
    }
    assays=libraries['feature_types'].unique()
    vdj_assays = []
    for assay in assays:
        if 'VDJ' in assay:
            if assay == 'VDJ':
                print("Auto-detection of VDJ assays not supported.")
                print("Specify a particular type of VDJ assay for 'feature_types' in 'libraries.csv'. Eg, 'VDJ-B' or 'VDJ-T'")
                exit()
            elif assay not in supported_vdj_assays.keys():
                print("Unsupported assay type: " + assay)
                exit()
            else:
                vdj_assays.extend([assay])
        else:
            # Non-VDJ assay
            pass 
    return [supported_vdj_assays.get(assay, assay) for assay in vdj_assays]

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
                        parameter = rename_map[parameter]
                    options=options+" --"+parameter
                else:
                    pass
            else:
                if type(value) is bool:
                    value=str(value).lower()
                options=options+" --"+parameter+" "+str(value)
        return options
    return handle_wildcards

# Return h5 files for given pool
def get_h5_in_pool(wildcards):
    capture_list = captures[captures['pool'] == wildcards.pool].index.tolist()
    return expand(out_dir/"h5/captures/{capture}/molecule_info.h5",capture=capture_list)

# Return pb files for given pool
def get_pb_in_pool(wildcards):
    capture_list = captures[captures['pool'] == wildcards.pool].index.tolist()
    return expand(
        out_dir/"vdj/{vdj_assay}/results/{capture}/vdj_contig_info.pb",
        capture=capture_list,
        vdj_assay=wildcards.vdj_assay
    )

# Returns individual source bam files to be merged as part of aggr
def get_source_bams(wildcards):
    capture_list = captures[captures["pool"] == wildcards.pool].index.tolist()
    source_bams = expand(
        out_dir/"bam/count/captures/{capture}/assigned_alignments.bam",
        capture=capture_list
    )
    return source_bams
