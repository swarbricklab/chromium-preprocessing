# This rule file contains functions defining pre-flight checks
# These checks ensure that the configuration files are well formed

# Make sure all assays match the supported assay-types
def check_assays():
    supported_assays=['gene-expression', 'feature', 'vdj']
    for assay in assays:
        if not assay in supported_assays:
            print("Unsupported assay type: {}".format)
            print("Only the follow assay types are supported {}".format(supported_assays))
            exit()
    return True

# Make sure we have a reference for each assay present
def check_refs():
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
def check_captures():
    capture_set=set(captures.index)
    fastq_set=set(libraries['fastq_id'].tolist())
    return capture_set == fastq_set

# If aggr enabled then make sure captures.csv has a pool column
# Default to true if not using aggr
def check_pool_column():
    return 'pool' in captures.columns or not config['params']['extras']['aggr']

# Make sure captures are unique per pool
def check_unique_captures():
    if not config['params']['extras']['aggr']:
        # Not using aggr so no pools
        return True
    else:
        for pool in captures['pool'].unique():
            capture_subset=captures.loc[captures['pool'] == pool]
            return capture_subset['capture'].is_unique

def preflight_check():
    preflight_checks = [
        check_assays,
        check_refs,
        check_captures,
        check_pool_column,
        check_unique_captures
    ]
    for check in preflight_checks:
        if not check():
            # Raise an exception immediately if a check fails.
            raise RuntimeError(f"Preflight check: failed {check.__name__}")
        else:
            print(f"Preflight check passed: {check.__name__}")
    print("All preflight checks passed!")
    return True


