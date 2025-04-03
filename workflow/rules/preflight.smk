# This rule file contains functions defining pre-flight checks
# These checks ensure that the configuration files are well formed

# Make sure all assays match the supported assay-types
def check_assays(assays):
    supported_assays=['gene-expression', 'feature', 'vdj']
    for assay in assays:
        if not assay in supported_assays:
            print("Unsupported assay type: {}".format)
            print("Only the follow assay types are supported {}".format(supported_assays))
            exit()
    return True

# Make sure we have a reference for each assay present
def check_refs(assays):
    for assay in assays:
        # Check if there is an entry in the config file under 'ref'
        if not assay in config["ref"]:
            print("Missing reference for {} in config file".format(assay))
            exit()
        # Make sure that specified reference exists
        if not os.path.exists(config["ref"][assay]):
            print("Reference not found: {}".format(config["ref"][assay]))
            exit()
    return True

# Check captures against libraries
# Here captures and libraries are pandas dataframes
# derived from captures.csv and libraries.csv
def check_captures(captures, libraries):
    capture_set=set(captures.index)
    fastq_set=set(libraries['fastq_id'].tolist())
    return capture_set == fastq_set