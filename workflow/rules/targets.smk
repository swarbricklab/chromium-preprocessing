"""
This rule file defines functions for determining which targets are enabled
when certain optional features are selected
"""

def get_vdj_assays_for_capture(capture):
    """
    Return VDJ assays available for a specific capture based on libraries.csv
    """
    supported_vdj_assays = {
        'VDJ-T': 'vdj_t',
        'VDJ-B': 'vdj_b'
    }
    # Get feature types for this capture from libraries.csv
    capture_libraries = libraries[libraries['fastq_id'] == capture]
    capture_assays = capture_libraries['feature_types'].unique().tolist()
    
    vdj_assays_for_capture = []
    for assay in capture_assays:
        if assay in supported_vdj_assays:
            vdj_assays_for_capture.append(supported_vdj_assays[assay])
    return vdj_assays_for_capture

def get_captures_with_vdj():
    """
    Return captures that have any VDJ assays
    """
    vdj_captures = []
    for capture in captures.index:
        if get_vdj_assays_for_capture(capture):
            vdj_captures.append(capture)
    return vdj_captures

def get_vdj_assays_in_pool(pool):
    """
    Return all VDJ assays present in captures within a pool
    """
    if 'pool' not in captures.columns:
        return []
    
    pool_captures = captures[captures['pool'] == pool].index.tolist()
    pool_vdj_assays = set()
    
    for capture in pool_captures:
        capture_vdj_assays = get_vdj_assays_for_capture(capture)
        pool_vdj_assays.update(capture_vdj_assays)
    
    return list(pool_vdj_assays)

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
        vdj_targets = []
        # Generate VDJ targets for each capture based on its specific assays from libraries.csv
        for capture in captures.index:
            capture_vdj_assays = get_vdj_assays_for_capture(capture)
            if capture_vdj_assays:
                vdj_targets.extend(
                    expand(
                        list(itertools.chain(
                            list(rules.restructure_vdj_fa.output),
                            list(rules.restructure_vdj_bams.output),
                            list(rules.restructure_vdj_loupe.output),
                            list(rules.restructure_vdj_annotations.output),
                            list(rules.restructure_vdj_results.output)
                        )),
                        capture=[capture], vdj_assay=capture_vdj_assays
                    )
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
    aggr_targets = []
    for pool in get_pool_list():
        pool_vdj_assays = get_vdj_assays_in_pool(pool)
        if pool_vdj_assays:
            aggr_targets.extend(
                expand(
                    list(rules.cellranger_aggr_vdj.output),
                    pool=[pool],
                    vdj_assay=pool_vdj_assays
                )
            )
    return aggr_targets

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
        # Generate VDJ targets for each capture based on its specific assays from libraries.csv
        for capture in captures.index:
            capture_vdj_assays = get_vdj_assays_for_capture(capture)
            if capture_vdj_assays:
                multi_targets.extend(
                    expand(
                        list(itertools.chain(
                            list(rules.restructure_raw_vdj_fa.output),
                            list(rules.restructure_multi_vdj_annotations.output),
                            list(rules.restructure_raw_vdj_bams.output)
                        )),
                        capture=[capture], vdj_assay=capture_vdj_assays
                ))
                for assay in capture_vdj_assays:
                    # Get samples for this capture
                    capture_samples = captures[captures['capture'] == capture]
                    if not capture_samples.empty:
                        sample_targets.extend(
                            expand(
                                list(itertools.chain(
                                    list(rules.restructure_sample_vdj_fa.output),
                                    list(rules.restructure_sample_vdj_annotations.output),
                                    list(rules.restructure_vdj_results.output),
                                    list(rules.restructure_vdj_loupe.output),
                                    list(rules.restructure_sample_vdj_bams.output)
                                )),
                                zip, capture=capture_samples['capture'].tolist(), 
                                sample=capture_samples['sample'].tolist(), 
                                vdj_assay=[assay] * len(capture_samples)
                            )
                        )

    return multi_targets + sample_targets
