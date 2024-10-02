# Chromium Preprocessing

## Overview

Pre-processing for raw Chromium data, including GE (gene expression), FB (CITE) and VDJ, as well as basic QC.
- [Modes](#modes)
- [Data preparation](#data-preparation)
- [Config](#config)
- [Tests](#tests)

## Modes

This workflow can be run in either [standalone mode](#standalone-mode) or [module mode](#module-mode).

### Standalone mode

In "standalone" mode, the data to be processed by the workflow is included in the same repo as the workflow itself.
This mode is used mainly for [testing](#tests).
This repo includes test data, tracked via DVC under [`test_data/raw`](https://github.com/swarbricklab/chromium-preprocessing/tree/main/test_data/raw).
The [config files](https://github.com/swarbricklab/chromium-preprocessing/tree/main/config/chromium-preprocessing) tracked in this repo have been configured to run the workflow on this test data.

### Module mode

This workflow can also be embedded into a dataset as a [git submodule](https://www.atlassian.com/git/tutorials/git-submodule).
This is how the workflow is applied to real-world data.

To use this workflow in "module mode", first [create a dataset repo](https://github.com/swarbricklab/data_management/blob/main/SOP/dataset_creation.md) to host all of the data relevant to the project, as well as all of the code used to process that data (which may include other modules and/or scripts in addition to this workflow).

TODO: Add notes for how to install any workflow as a submodule; link to those notes here

Be sure to [prepare the data](#data-preparation) and [configure the workflow](#config) to process that data. 

## Data preparation

When used in module mode, all of the data to be processed by the workflow should be added to the dataset.
This includes:
- [raw data](#raw-data) (fastqs from 10X captures)
- [resources](#resources) (reference transcriptomes, etc)

This data should be dvc-tracked as part of a dataset that includes all of the data associated with that project.

### Raw data

The raw data should already be [registered](https://github.com/swarbricklab/data_management) in the appropriate registry.
If not, make a ticket in the [registries project board](https://github.com/orgs/swarbricklab/projects/5).
For this workflow, the relevant registry is [chromium](https://github.com/swarbricklab/chromium).

[Import](https://dvc.org/doc/command-reference/import) the data from the registry into the dataset as follows:
```
dvc import {registry} {path in registry} -o {path in dataset}
```
Here `{registry}` is the SSH git URL for the registry.
For example, URL for the `chromium` registry is `git@github.com:swarbricklab/chromium.git`

`{path in registry}` is the path to the data within the registry.
You can either look up the path in the [index](https://github.com/swarbricklab/chromium/blob/main/index.csv) or browse the official instance of the registry on NCI at the following path:
```
/g/data/dvc/instances/chromium
```
(This example is for the `chromium` registry.)
> Note: paths in the registry should be specified relative to the top of the registry.
> That is, paths should not start with `/g/data/` etc.

`{path in dataset}` is the location where you want to import the data into the dataset.
Typically, raw data will be imported to `data/fastqs` or similar.
In a multi-modal project (with single cell data and other modalities), you might want to add extra layers to organise data by modality.
For example: `data/sc/fastqs`

Importing data in this way will create `.dvc` files to track the import.
These `.dvc` files should be tracked via git in the dataset repository.

### Resources

In the context of this workflow, resoures include reference transcriptomes and probe sets.
These resources should also be dvc-tracked as part of the dataset repo.

There are three ways of adding these resources:
1. [import](https://dvc.org/doc/command-reference/import) the resource from the [references](https://github.com/swarbricklab/references) registry (see the `10X/` folder in particular)
2. copy the resources from the workfow repo (this repo) to the dataset repo
3. add the resources directly to the dataset

Here 1) is the preferred option.
If you cannot locate the resources that you need in the [references](https://github.com/swarbricklab/references) registry then [create an issue](https://github.com/swarbricklab/references/issues/new) to have it added as it is very likely that others will need it too.

Option 2) may be convenient if you are working with human cells and poly-A captures. 
In this case, copy the entire content of the `resources/` directory in order to include `.gitignore` files correctly.
Use `rsync` rather than `cp` to avoid clobbering any existing files in the `resources/` directory of the dataset repo.
Finally, be sure to `dvc pull` the actual data prior to running the workflow.
```
rsync -av --ignore-existing modules/chromium-preprocessing/resources resources/
dvc pull -R resources
```
Run this command from the top of the dataset repo, assuming that this workflow repo has been installed as a git submodule at `modules/chromium-preprocessing/`.
Adjust the path if necessary.

Option 3 should only be a last resort. 
Beter to add the resources to the [references](https://github.com/swarbricklab/references) registry to make life easier for others.

## Config

To run this workflow, you will need to edit the following files:
- [config.yaml](config/chromium-preprocessing/config.yaml)
- [ge_captures](config/chromium-preprocessing/ge_captures.csv)
- [pep_config.yaml](config/chromium-preprocessing/pep_config.yaml)
- [ge_aggr.tsv](config/chromium-preprocessing/ge_aggr.tsv) (if running `aggr``)

When using this workflow as a module, copy these files across to the super project.
```
cd {top of super project}
mkdir -p config/chromium-preprocessing
cp modules/chromium-preprocessing/config/* config/chromium-preprocessing 
```

### config.yaml

[config.yaml](config/chromium-preprocessing/config.yaml) contains the following three elements:
- `cellranger` version information (container reference)
- `count` options
- `aggr` options

TO DO: Add `multi` options

#### Version options

`cellranger` runs inside a Docker container, which is converted to Singularity format when running on a HPC.
If you need a more recent version, you might need to locate or build a container for that version of `cellranger`.

#### `count` options

The specifications below the `count` block are passed in to `cellranger count`.
Core parameters, such as the location of the fastqs are passed in via the capture sheet.
But you can further control `cellranger` behaviour by passing in additional "flags" such as `--no-secondary`. 
Multiple flags can be combined into a single string.
For example, `--no-secondary --include-introns`.

See the [Cellranger Manual](https://www.10xgenomics.com/support/software/cell-ranger/7.2/resources/cr-command-line-arguments) for more options.
Note: this link is for v7.2 -- switch versions if you are using a different version.

#### `aggr` options

The specifications below the `aggr` block are passed in to `cellranger aggr`.
This works in much the same way as for `count` above.
See that section for further details and examples, including external references.

### ge_captures.csv

This sample sheet (or more strictly speaking, "capture sheet") is used for `cellranger count`. 
[This file](config/chromium-preprocessing/ge_captures.csv) lists the captures to be processed and the locations of the gene expression fastq files for each capture.

This CSV file expects two columns:
- `capture_id`
- `ge_fastqs`

If there are multiple fastq paths for a given capture (such as when a capture is sequenced over multiple flow cells) then list each path on the same row, separated by semicolons.

Note: if the locations of the fastq files follow a consistent pattern based on the name of the capture, then it may be convenient to define that pattern in [pep_config.yaml](config/chromium-preprocessing/pep_config.yaml) rather than enter each path manually.
See the section below for an example of how this works.
However, if the fastq paths are inconsistent and difficult to capture with a simple pattern then it may be easier to simply enter the paths manually under the `ge_fastqs` column.

### pep_config.yaml

This file follows the [Portable Encapsulated Projects](https://pep.databio.org/) (PEP) format, which -- as the name suggests -- is intended to make projects both portable by handling file paths in a consistent manner.

> While relatively simple, PEP has gained very little traction within the group, and might be phased out in favour of other strategies, such as consolidating these specifications in a single config file 

The contrast between `config.yaml` and `pep_config.yaml` is that the former defines _how_ the workflow runs by specifying the versions and options for the software tools used in the workflow, whereas the latter defines _where_ the data is located.

`pep_config.yaml` contains the following three blocks of specifications:
- headers
- interface
- synthetic columns

#### Headers

This section can be mostly left unchanged.
If desired, change the name of the CSV file loaded in `sample_table`.
Do not change the index column (`capture_id`).

#### Interface

This section defines the inputs, outputs and resources used by the workflow.
For example, the output paths for all rules start with `output.cr_outs`.
This makes it possible to redirect the outputs for this workflow by changing this single parameter.

> The intention was to use this "interface" definition to automatically create a "stage" in `dvc.yaml`, with the `deps` and `outs` for the staged population based on the specifications here. 
> However, given the poor uptake of PEP this avenue might not be persued.

This section is required.
No editing is required, unless you want to redirect inputs or outputs.

#### Synthetic columns

This section makes it possible to define "synthetic columns" in the sample sheet.
Specifically, if the path for `ge_fastqs` follows a consistent pattern for all samples, then this pattern can be defined by `sample_modifiers`.
See the [sample pep_config.yaml](config/chromium-preprocessing/pep_config.yaml) in this repo for an example of how this is done with the test data.

This section is optional.

> If there is no consistent pattern, or if the pattern is difficult to capture, then it is often easier to just specify the paths manually in the capture sheet.

## Tests

This module includes test data and a test script that veriies that the module can process this test data into the expected results.

### Test data

The [test_data](test_data) folder contains both the raw test data (under `test_data/raw/`) and the expected results (under `test_data/results`).
The input data (`test_data/raw/`) is real 10X Chromium scRNA-seq data that has been downsampled to make the fastq files much smaller, so that `cellranger` runs much faster.
This data is tracked via DVC and can be obtained via `dvc pull -R test_data/`.
Same goes to the reference data, obtained via `dvc pull resources/transcriptomes/refdata-gex-GRCh38-2020-A`.

## Test config

The example [config files](config/chromium-preprocessing) in this repo are set up in order to process the [test data](#test-data) above.
When running this workflow on other datasets (either in "module mode" or "standalone mode") then these config files will need to be edited.
But when running the [test script](#test-script) below these config files can be left unchanged.

### Test script

The [run_test.sh](run_test.sh) script runs the module on the [test data](#test-data) above.
This script assumes that 
1. the test data is available (pulled via DVC)
2. a conda environment called `snakemake_7.32.4` is available

The script runs the workflow by calling `snakemake` with the appropriate [config](#test-config) and profile, and then compares the results with the expected results in `test_data/results/` by doing a selective `diff`.
Any differences will be reported.

### Test results

There are (at least) two scenarios when it can be helpful to run the [test script(#test-script):
1. practicing how to run the workflow
2. testing whether improvements to the workflow have broken existing functionality

In the latter case, it is possible that the improvements result in additional or different test results.
If this happens, then update `test_data/results/` to capture the results that should be expected with the latest version of the workflow.
```
rm -rf test_data/results          # don't worry, we can always 'dvc pull' it again
cp -r  results test_data/results
dvc commit test_data/results
```
Make any such changes via git issues and pull requests.

## Logs

All log files are output to one of the the following locations:
1. `logs/joblogs/`
2. `logs/chromium-preprocessing/{rule}`

Job logs are produced by the PBS Pro job scheduler when rules are submitted as jobs via the global profile under `profiles/global`.

Rule logs capture key outputs for each rule, redirected to a log file. 
Thes logs are stored under `logs/chromium-preprocessing` in a subdirectory based on the rule name.

Both log directories above should be added to the "outs" for the `chromium-preprocessing` stage in `dvc.yaml` when this workflow is used as a module within a larger DVC pipeline.