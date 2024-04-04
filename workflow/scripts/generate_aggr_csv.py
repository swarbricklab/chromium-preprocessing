# ===================
# title: "generate_aggr_csv"
# description: Generates csv files for use in cellranger aggr 
# project: "workflow-chromium-preprocessing"
# author: "Daniel Roden"
# email: "d.roden@garvan.org.au"
# company: "Garvan Institute"
# created: 29/06/2023
# -------------------
# NOTE: this is a snakmake script that uses the "snakemake" object internals
# ===================

import pandas as pd
import logging as log
import itertools

log.basicConfig(filename = snakemake.log[0], 
                    level = log.INFO, 
                    format = '%(asctime)s:%(levelname)s:%(message)s')                    
log.info("LOG FILE: " + snakemake.log[0])

log.info("----------------------------------") 
log.info("CONFIG")
log.info("----------------------------------") 
log.info("INPUT")

# ----------
# DEBUG
debug = False
if debug:
    print("DEBUG")
    # TODO
# ----------
    

file_sample_sheet = snakemake.input["sample_sheet"]
log.info("file_sample_sheet: " + file_sample_sheet)


log.info("OUTPUT")
file_aggr_csv = snakemake.output["aggr_csv"]
log.info("file_aggr_csv: " + file_aggr_csv)

log.info("")

log.info("WILDCARDS")
aggr_id = snakemake.wildcards["aggr_id"]
log.info("aggr_id: " + aggr_id)
log.info("")

log.info("PARAMS")
cr_outs = snakemake.params["cr_outs"]
log.info("cr_outs: " + cr_outs)
log.info("")

log.info("----------------------------------") 

# parse sample-sheet
df_sample_sheet = pd.read_csv(file_sample_sheet, sep = "\t", dtype = {'capture_id': str, 'aggr_id': str})

# select captures associated with current aggr_id
df_sample_sheet = df_sample_sheet.loc[df_sample_sheet["aggr_id"] == aggr_id, ["capture_id"]]
capture_ids = df_sample_sheet["capture_id"].tolist()

log.info("Identified " + str(len(capture_ids)) + " captures to aggregate")
log.info(" ".join(capture_ids))

# build df with capture_id and associated h5 file path (relative to csv file)
h5_paths = []
for capture_id in capture_ids:
    h5_paths.append("../../../../" + cr_outs + '/' + str(capture_id) + "/outs/molecule_info.h5")

data = {'sample_id': capture_ids,
        'molecule_h5': h5_paths}
df_aggr = pd.DataFrame(data)

# write to file
df_aggr.to_csv(file_aggr_csv, sep=',', index=False, header=True)

log.info("----------------------------------") 
log.info("PROCESSING COMPLETE")
log.info("----------------------------------") 
