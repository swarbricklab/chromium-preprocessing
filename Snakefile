import pandas as pd
from pathlib import Path
from snakemake.utils import validate

captures=pd.read_csv(config['deps']['captures']).set_index('capture', drop=False)
validate(captures, "workflow/schemas/captures.json")
libraries=pd.read_csv(config['deps']['libraries'])
validate(libraries,"workflow/schemas/libraries.json")

out_dir=Path(config['outs']['results'])

include: 'workflow/rules/preflight.smk'
include: 'workflow/rules/common.smk'
include: 'workflow/rules/summarise.smk'

# Find which assays and VDJ sub-assays are present in the libraries
assays = find_assays(libraries)
if 'vdj' in assays:
    vdj_assays = find_vdj_assays(libraries)

if not preflight_check():
    exit()

# The following section dynamically loads rule files depending on config choices
# and validates config schemas according to these selections
# A list of final targets is built depending on these choices.

targets = []

if assays == ['gene-expression']:
    # When only gene-expression libraries are present use 'cellranger count.
    print("Running cellranger count")
    include: 'workflow/rules/cellranger_count.smk'
    include: 'workflow/rules/restructure_count.smk'
    validate(config,"workflow/schemas/multi.json")
    targets.extend(count_targets())
elif assays == ['vdj']:
    # Technically 'cellranger vdj' allows VDJ libraries to be processed alone
    # But so far we never do this, so there are no rules defined for this case
    print("No support for 'cellranger vdj' yet")
    print("Use multi by providing gene expression libraries as well")
else:
    # Use 'cellranger multi' if more than one assay present
    print("Running cellranger multi")
    include: 'workflow/rules/cellranger_multi.smk'
    include: 'workflow/rules/restructure_multi.smk'
    validate(config,"workflow/schemas/multi.json")
    targets.extend(multi_targets())
# Optionally use 'cellranger aggr' to aggregate split pools
if config['params']['extras']['aggr']:
    print("Running cellranger aggr")
    include: 'workflow/rules/cellranger_aggr.smk'
    targets.extend(aggr_targets())
    validate(config,"workflow/schemas/aggr.json")
    validate(captures, "workflow/schemas/aggr_captures.json")


rule all:
    input:
        targets


