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

# Annotate by sample if hto demux is enabled but by capture otherwise

if config['params']['extras'].get('hto', False) or config['params']['extras'].get('ocm', False):
    # Annotate by sample
    rule annotate_sample:
        """
        Annotate sample count matrix by cell type via 10X Cloud
        """
        input:
            check=rules.cloud_auth.output.check,
            h5=rules.restructure_h5.output.mat,
            loupe=rules.restructure_loupe.output.cloupe
        output:
            ann_dir=temp(directory(out_dir/"annotation_tmp/{capture}/{sample}"))
        log:
            log_dir/"annotate/{capture}/{sample}.log"
        envmodules:
            "cellranger/9.0.1"
        shell:
            """
            wd=$PWD
            cd $(dirname {output.ann_dir})
            cellranger annotate \
                --id {wildcards.sample} \
                --matrix $wd/{input.h5} \
                --cloupe $wd/{input.loupe} \
                > $wd/{log} 2>&1
            """

    rule restructure_annotations:
        """
        Move annotation outputs to correct structure
        """
        input:
            cr_dir=rules.annotate_sample.output.ann_dir
        output:
            types=out_dir/"annotation/{capture}/{sample}/cell_types.csv",
            de=out_dir/"annotation/{capture}/{sample}/cell_annotation_differential_expression.csv",
            json=out_dir/"annotation/{capture}/{sample}/cell_annotation_results.json.gz",
            web=report_dir/"cellranger/cell_types/captures/{capture}/{sample}.html"
        shell:
            """
            outs={input.cr_dir}/outs
            cp -r $outs/cell_types.csv {output.types}
            cp -r $outs/cell_annotation_differential_expression.csv {output.de}
            cp -r $outs/cell_annotation_results.json.gz {output.json}
            cp -r $outs/web_summary_cell_types.html {output.web}
            """
else:
    # Annotate by capture
    rule annotate_capture:
        """
        Annotate capture count matrix by cell type via 10X Cloud
        """
        input:
            check=rules.cloud_auth.output.check,
            h5=rules.restructure_h5.output.mat,
            loupe=rules.restructure_loupe.output.cloupe
        output:
            ann_dir=temp(directory(out_dir/"annotation_tmp/{capture}"))
        log:
            log_dir/"annotate/{capture}.log"
        envmodules:
            "cellranger/9.0.1"
        shell:
            """
            log_file=$PWD/{log}
            h5=$PWD/{input.h5}
            loupe=$PWD/{input.loupe}
            cd $(dirname {output.ann_dir})
            cellranger annotate \
                --id {wildcards.capture} \
                --matrix $h5 \
                --cloupe $loupe \
                > $log_file 2>&1
            """

    rule restructure_annotations:
        """
        Move annotation outputs to correct structure
        """
        input:
            cr_dir=rules.annotate_capture.output.ann_dir
        output:
            types=out_dir/"annotation/{capture}/cell_types.csv",
            de=out_dir/"annotation/{capture}/cell_annotation_differential_expression.csv",
            json=out_dir/"annotation/{capture}/cell_annotation_results.json.gz",
            web=report_dir/"cellranger/cell_types/captures/{capture}.html"
        shell:
            """
            outs={input.cr_dir}/outs
            cp -r $outs/cell_types.csv {output.types}
            cp -r $outs/cell_annotation_differential_expression.csv {output.de}
            cp -r $outs/cell_annotation_results.json.gz {output.json}
            cp -r $outs/web_summary_cell_types.html {output.web}
            """