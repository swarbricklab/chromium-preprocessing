import pandas as pd
from pathlib import Path
from snakemake.utils import validate

captures=pd.read_csv(config['deps']['captures']).set_index('capture', drop=False)
validate(captures, "workflow/schemas/captures.json")
libraries=pd.read_csv(config['deps']['libraries'])
validate(libraries,"workflow/schemas/libraries.json")

out_dir=Path(config['outs']['results'])
report_dir=Path(config['outs']['reports'])
log_dir=Path(config['outs']['logs'])

include: 'workflow/rules/preflight.smk'
include: 'workflow/rules/common.smk'
include: 'workflow/rules/targets.smk'
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

targets = [report_dir/"cellranger/master_index.html"]

if assays == ['gene-expression']:
    # When only gene-expression libraries are present use 'cellranger count.
    print("Running cellranger count")
    include: 'workflow/rules/cellranger_count.smk'
    include: 'workflow/rules/restructure_count.smk'
    validate(config,"workflow/schemas/count.json")
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
    if config['params']['extras']['hto'] or config['params']['extras']['ocm']:
        samples=pd.read_csv(config['deps']['captures']).set_index('sample', drop=False)
        if config['params']['extras']['hto']:
            print("Running HTO demux")
            validate(captures,"workflow/schemas/hto.json")
        else:
            print("Running OCM demux")
            validate(captures,"workflow/schemas/ocm.json")
        include: 'workflow/rules/restructure_hto_ocm.smk'
        targets.extend(hto_ocm_targets())
    else:
        include: 'workflow/rules/restructure_multi.smk'
        validate(config,"workflow/schemas/multi.json")
        targets.extend(multi_targets())
# Optionally use 'cellranger aggr' to aggregate split pools
if config['params']['extras']['aggr']:
    print("Running cellranger aggr")
    include: 'workflow/rules/cellranger_aggr.smk'
    targets.extend(aggr_count_targets())
    if 'vdj' in assays:
        targets.extend(aggr_vdj_targets())
    validate(config,"workflow/schemas/aggr.json")
    validate(captures, "workflow/schemas/aggr_captures.json")

# Optionally run the 'pre-demux' filtering workflow
if config['params']['extras']['predemux']:
    print("Running pre-demux cell filtering")
    include: 'workflow/rules/predemux.smk'
    targets.extend(predemux_targets())
    validate(config, "workflow/schemas/predemux.json")

# Optionally use 'cellranger annotate' to assign cell type labels
if config['params']['extras']['annotate']:
    print("Running cellranger annotate")
    include: 'workflow/rules/annotate.smk'
    targets.extend(annotate_targets())

include: 'workflow/rules/html_reports.smk'

wildcard_constraints:
    capture = "[^/]+"

rule all:
    input:
        targets
