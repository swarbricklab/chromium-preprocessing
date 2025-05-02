# This rule file defines rules for annotating celltypes based on 10X Cloud
# This assumes that the user has already authenticated

rule cloud_auth:
    """
    Verify that the execution user is authenticated to 10X Cloud
    """
    output:
        check=out_dir/"checks/auth.check"
    envmodules:
        "cellranger/9.0.1"
    shell:
        """
        cellranger cloud auth verify > {output.check} 2>&1
        """

rule annotate:
    """
    Annotate count matrix by cell type via 10X Cloud
    """
    input:
        check=rules.cloud_auth.output.check,
        h5=rules.restructure_h5.output.filtered_mat,
        loupe=rules.restructure_loupe.output.filtered
    output:
        ann_dir=temp(directory("{capture}"))
    log:
        log_dir/"annotate/{capture}.log"
    envmodules:
        "cellranger/9.0.1"
    shell:
        """
        rm -rf {output.ann_dir}
        cellranger annotate \
            --id {wildcards.capture} \
            --matrix {input.h5} \
            --cloupe {input.loupe} \
            > {log} 2>&1
        """

rule restructure_annotations:
    """
    Move annotation outputs to correct structure
    """
    input:
        cr_dir=rules.annotate.output.ann_dir
    output:
        types=out_dir/"annotation/{capture}/cell_types.csv",
        de=out_dir/"annotation/{capture}/cell_annotation_differential_expression.csv",
        json=out_dir/"annotation/{capture}/cell_annotation_results.json.gz",
        web=report_dir/"web/captures/cell_types/{capture}.html"
    shell:
        """
        outs={input.cr_dir}/outs
        cp -r $outs/cell_types.csv {output.types}
        cp -r $outs/cell_annotation_differential_expression.csv {output.de}
        cp -r $outs/cell_annotation_results.json.gz {output.json}
        cp -r $outs/web_summary_cell_types.html {output.web}
        """
        