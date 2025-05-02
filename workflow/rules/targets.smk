"""
This rule file defines functions for determining which targets are enabled
when certain optional features are selected
"""

# --- count ---
def count_targets():
    """
    The following targets are enabled if 'Gene Expression' is the only assay 
    in 'libraries.csv'
    """
    count_targets = expand(
        list(itertools.chain(
            list(rules.restructure_counts.output),
            list(rules.restructure_summary.output),
            list(rules.restructure_h5.output),
            list(rules.restructure_loupe.output)
        )),
        capture=captures.index
    )
    if config['params']['gene-expression']['create-bam']:
        count_targets.extend(
            expand(list(rules.restructure_bams.output),capture=captures.index)
        )
    if not config['params']['gene-expression']['no-secondary']:
        count_targets.extend(
            expand(rules.restructure_analysis.output.dir,capture=captures.index)
        )
    return count_targets

# --- multi ---
def multi_targets():
    """
    The following targets are enabled if more than one assay is specified
    in 'libraries.csv' (eg 'Gene Expression' + 'VDJ-T')
    """
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

# --- anotate ---
def annotate_targets():
    """
    The following targets are enabled if 'params.extras.annotate' is 'true'
    """
    return expand(
        list(rules.restructure_annotations.output),
        capture = captures.index
    )

# --- aggr  ---
def aggr_count_targets():
    """
    The following targets are enabled if 'params.extras.aggr' is 'true'
    """
    aggr_count_targets=expand(
        list(itertools.chain(
            list(rules.merge_bams.output),
            list(rules.index_merged_bam.output),
            list(rules.restructure_aggr_counts.output),
            list(rules.restructure_aggr_summary.output),
        )),
        pool=get_pool_list()
    )
    if not config['params']['gene-expression']['no-secondary']:
        aggr_count_targets.extend(
            expand(rules.restructure_aggr_analysis.output.dir,pool=get_pool_list())
        )
    return aggr_count_targets

def aggr_vdj_targets():
    """
    The following targets are enabled if 'params.extras.aggr' is 'true' AND
    VDJ libraries are present
    """
    return expand(
        list(rules.cellranger_aggr_vdj.output),
        pool=get_pool_list(),
        vdj_assay=vdj_assays
    )
