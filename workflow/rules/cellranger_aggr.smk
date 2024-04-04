# rule to generate input csv config files for aggr
# use an aggr_id column in config sample-sheet
rule generate_aggr_csv:
    input:
        sample_sheet=config["aggr"]["samples"]
    output:
        aggr_csv=pep.config.output.cr_outs + "/aggr/csvs/{aggr_id}.csv"
    params:
        cr_outs=pep.config.output.cr_outs
    resources:
        cores="1",
        mem="16GB"
    conda:
        "../envs/generate_aggr_csv.yaml"
    log:
        pep.config.output.cr_outs + "/aggr/csvs/{aggr_id}.generate_aggr_csv.log"
    script:
        "../scripts/generate_aggr_csv.py"

# rule to run cellranger aggr on defined aggr_id groups
rule cellranger_aggr:
    input:
        aggr_csv=pep.config.output.cr_outs + "/aggr/csvs/{aggr_id}.csv",
        molecule_h5=get_cellranger_aggr_aggr_captures_input
    output:
        out_dir=directory(pep.config.output.cr_outs + "/aggr/output/{aggr_id}"),
        summary=pep.config.output.cr_outs + "/aggr/output/{aggr_id}/outs/count/summary.json"
    resources:
        cores="16",
        mem="110GB",
        tmp_requested="100G",
        tmpfree="100G"
    params:
        flags=config['aggr_flags']
    container:
        config["cr_container_publisher"] + config["cr_version"]
    log:
        pep.config.output.cr_outs + "/aggr/{aggr_id}.cellranger_aggr.log"
    script:
        "../scripts/cellwrapper_aggr.sh"