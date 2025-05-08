"""
This rule file defines functions for determining which targets are enabled
when certain optional features are selected
"""

def get_pool_list():
    """
    Return a list of valid pools
    Valid pools do not have the same value as the capture in the same row
    Valid pools cannot be 'NA', 'None' or the empty string
    """
    null_pool_indicators = ['', 'NA', 'None']
    valid_pools = captures.loc[(captures['pool'] != captures.index) | (captures['pool'].isin(null_pool_indicators))]
    return valid_pools['pool'].unique().tolist()

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
            list(rules.restructure_raw_h5.output),
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
    if config['params']['extras']['hto']:
        # Annotating by sample
        return expand(
            list(rules.restructure_annotations.output),
            zip, capture = captures['capture'], sample=captures['sample']
        )
    else:
        # Annotating by capture
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

# --- hto ---
def hto_targets():
    """
    The following targets are enabled if 'params.extra.hto' is 'true'
    """
    multi_targets = expand(
        list(itertools.chain(
            list(rules.restructure_multiplexing_analysis.output),
            list(rules.restructure_raw_counts.output),
            list(rules.restructure_raw_h5.output),
            list(rules.restructure_raw_loupe.output)
        )),
        capture=captures.index
    )
    sample_targets = expand(
        list(itertools.chain(
            list(rules.restructure_summary.output),
            list(rules.restructure_sample_counts.output),
            list(rules.restructure_h5.output),
            list(rules.restructure_loupe.output),
            list(rules.restructure_analysis.output)
        )),
        zip, capture=captures['capture'], sample=captures['sample']
    )

    if config['params']['gene-expression']['create-bam']:
        multi_targets.extend(
            expand(
                list(rules.restructure_unassigned_bams.output),
                capture=captures.index
            )
        )
        sample_targets.extend(
            expand(
                list(rules.restructure_assigned_bams.output),
                zip,capture=captures['capture'], sample=captures['sample']
             )
        )

    if not config['params']['gene-expression']['no-secondary']:
        sample_targets.extend(
            expand(
                list(rules.restructure_analysis.output.dir),
                zip, capture=captures['capture'], sample=captures['sample']
            )
        )
    if 'vdj' in assays:
        multi_targets.extend(
            expand(
                list(itertools.chain(
                    list(rules.restructure_raw_vdj_fa.output),
                    list(rules.restructure_multi_vdj_annotations.output),
                    list(rules.restructure_raw_vdj_bams.output)
                )),
                capture=captures.index, vdj_assay=vdj_assays
        ))
        for assay in vdj_assays:
            sample_targets.extend(
                expand(
                    list(itertools.chain(
                        list(rules.restructure_sample_vdj_fa.output),
                        list(rules.restructure_sample_vdj_annotations.output),
                        list(rules.restructure_vdj_results.output),
                        list(rules.restructure_vdj_loupe.output),
                        list(rules.restructure_sample_vdj_bams.output)
                    )),
                    zip, capture=captures['capture'], sample=captures['sample'], vdj_assay=assay
                )
            )

    return multi_targets + sample_targets
