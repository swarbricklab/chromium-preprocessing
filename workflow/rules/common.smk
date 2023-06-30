from snakemake.io import expand
import pandas as pd

# Look up field in sample_sheet
def capturesheet(field):
    def handle_wildcards(wildcards):
        return captures.loc[wildcards.capture, field]
    return handle_wildcards


# get rule all input files for cellranger aggr
def aggr_all(wildcards):

    aggr_input = []

    if config["aggr"]["activate"]:
        # parse sample-sheet
        df_sample_sheet = pd.read_csv(config["aggr"]["samples"], sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

        aggr_ids = list(set(df_sample_sheet["aggr_id"].tolist()))
        # remove dummy aggr_id that signifies NOT to aggregate these captures
        aggr_ids.remove("NONE")
        
        aggr_input.extend(
            expand([
                pep.config.output.cr_outs + "/aggr/csvs/{aggr_id}.csv",
                pep.config.output.cr_outs + "/aggr/output/{aggr_id}/outs/count/summary.json"
            ],
                aggr_id=aggr_ids
            )
        )

    return aggr_input