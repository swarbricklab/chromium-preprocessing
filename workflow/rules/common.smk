from snakemake.io import expand
import pandas as pd
import itertools

# Determine which assays are present in libraries.csv
def find_assays(libraries):
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
                        parameter = rename_map['parameter']
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
    return expand(out_dir/"h5/{capture}/molecule_info.h5",capture=capture_list)

# Return a list of valid pools
# Valid pools do not have the same value as the capture in the same row
# Valid pools cannot be 'NA', 'None' or the empty string
def get_pool_list():
    null_pool_indicators = ['', 'NA', 'None']
    valid_pools = captures.loc[(captures['pool'] != captures.index) | (captures['pool'].isin(null_pool_indicators))]
    return valid_pools['pool'].unique().tolist()

# get rule all input files for cellranger aggr
def aggr_targets():
    return expand(
        [   
            out_dir/"aggr/{pool}/outs/count/summary.json",
            out_dir/"bams/{pool}/merged.bam.bai"
        ],
        pool=get_pool_list()
    )

def count_targets():
    count_targets = expand(list(rules.restructure_counts.output),capture=captures.index)
    if config['params']['gene-expression']['create-bam']:
        count_targets.extend(
            expand(list(rules.restructure_bams.output),capture=captures.index)
        )
    if not config['params']['gene-expression']['no-secondary']:
        count_targets.extend(
            expand(rules.restructure_analysis.output.dir,capture=captures.index)
        )
    return count_targets

def multi_targets():
    multi_targets=count_targets()
    if 'vdj' in assays:
        vdj_targets=expand(
            list(itertools.chain(
                list(rules.restructure_vdj_fa.output),
                list(rules.restructure_vdj_bams.output),
                list(rules.restructure_vdj_loupe.output),
                list(rules.restructure_vdj_annotations.output),
                list(rules.restructure_vdj_results.output)
            )),
            capture=captures.index, vdj_assay=vdj_assays
        )
    multi_targets.extend(vdj_targets)
    return multi_targets

# Returns individual source bam files to be merged as part of aggr
def get_source_bams(wildcards):
    capture_list = captures[captures["pool"] == wildcards.pool].index.tolist()
    source_bams = expand(
        out_dir/"bam/count/{capture}/assigned_alignments.bam",
        capture=capture_list
    )
    return source_bams
