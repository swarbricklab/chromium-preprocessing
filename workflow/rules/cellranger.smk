rule cellranger_count:
    input:
        fastqs=capturesheet("ge_fastqs")
    output:
        out_dir=directory(pep.config.output.cr_outs + "/{capture}"),
        molecule_h5=pep.config.output.cr_outs + "/{capture}/outs/molecule_info.h5",
        summary=pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv"
    resources:
        cores="16",
        mem="110GB",
        tmp_requested="100G",
        tmpfree="100G"
    params:
        transcriptome=pep.config.resources.transcriptome,
        flags=config['count_flags']
    container:
        config["cr_container_publisher"] + config["cr_version"]
    log:
        "logs/cr_count/{capture}.log"
    script:
        "../scripts/cellwrapper_count.sh"


rule cr_summarise:
    input:
        individual_summaries=expand(
            pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv", 
            capture=captures["capture_id"]
        )
    output:
        group_summary=pep.config.output.cr_outs + "/cr_summary.csv"
    params:
        groups=','.join(captures["capture_id"])
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > {output.group_summary}
        """


# TODO: rule to generate input csv config files for aggr
#       use an aggr_id column in config sample-sheet

rule cellranger_aggr:
    input:
        aggr_csv="temp/{aggr_id}.csv"
        # TODO: input function to define the h5 files for each aggr job
        molecule_h5=expand(pep.config.output.cr_outs + "/{aggr_captures}/outs/molecule_info.h5", aggr_captures = ["TNBC_001, TNBC_002"] 
    output:
        out_dir=directory(pep.config.output.cr_outs + "/aggr/{aggr_id}"),
        summary=pep.config.output.cr_outs + "/aggr/{aggr_id}/outs/summary.json"
        #summary=pep.config.output.cr_outs + "/{capture}/outs/metrics_summary.csv"
        #
        # Outputs:
        # - Aggregation metrics summary HTML:         /home/jdoe/runs/AGG123/outs/web_summary.html
        # - Copy of the input aggregation CSV:        /home/jdoe/runs/AGG123/outs/aggregation.csv
        # - Aggregation metrics summary JSON:         /home/jdoe/runs/AGG123/outs/summary.json
        # - Secondary analysis output CSV:            /home/jdoe/runs/AGG123/outs/analysis
        # - Filtered feature-barcode matrices MEX:    /home/jdoe/runs/AGG123/outs/filtered_feature_bc_matrix
        # - Filtered feature-barcode matrices HDF5:   /home/jdoe/runs/AGG123/outs/filtered_feature_bc_matrix.h5
        # - Loupe Browser file:                       /home/jdoe/runs/AGG123/outs/cloupe.cloupe        
    resources:
        cores="16",
        mem="110GB",
        tmp_requested="100G",
        tmpfree="100G"
    params:
        #transcriptome=pep.config.resources.transcriptome,
        flags=config['aggr_flags']
    container:
        config["cr_container_publisher"] + config["cr_version"]
    log:
        "logs/cr_count/{capture}.log"
    script:
        "../scripts/cellwrapper_aggr.sh"    
    # shell:
    #     """
    #     cellranger aggr --id=AGG123 --csv=AGG123_libraries.csv
    #     """


