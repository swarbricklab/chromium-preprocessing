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
This repo includes test data, tracked via DVC under [test/data](test/data).
The [test config files](config/tests) tracked in this repo have been configured to run the workflow on this test data.

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

When using this workflow as a module, copy these files across to the super project.
For `{mode}` specify "count" if only gene expression (RNA) libraries are used, or "multi" if feature barcode (CITE/ADT/HTO) or VDJ libraries are also included.
```
cd {top of super project}
mkdir -p config/chromium-preprocessing
cp modules/chromium-preprocessing/config/templates/{mode} config/chromium-preprocessing 
```

To run this workflow, you will need to edit the following files within `config/chromium-preprocessing`:
- `config.yaml` ([template](config/templates/multi/config.yaml)) ([test config](config/tests/multi/config.yaml))
- `captures.csv` ([template](config/templates/multi/captures.csv)) ([test config](config/tests/multi/captures.csv))
- `libraries.csv` ([template](config/templates/multi/libraries.csv)) ([test config](config/tests/multi/libraries.csv))

Refer to the [configuration guide](config/README.md) for a detailed explanation and see the templates and test config linked above for examples.

## Tests

This module includes test data and a test script that verifies that the module can process this test data into the expected results.

### Test data

The [test](test) folder contains both the raw test data (under [test/data](test/data)) and the expected results (under [test/results](test/results)).
The input data is real 10X Chromium scRNA-seq data that has been downsampled to make the fastq files much smaller, so that `cellranger` runs much faster.
This data is tracked via DVC and can be obtained via `dvc pull -R test/data/`.

## Test config

As well as [template config](config/templates/), this repo includes [test config](config/tests/) for running the workflow on the test data bundled with this repo.

### Test script

The [run_test.sh](run_test.sh) script runs test on the [test data](#test-data) above.
This script assumes that 
1. the test data is available (pulled via DVC)
2. a conda environment called `snakemake_7.32.4` is available

The script runs the workflow by calling `snakemake` with the appropriate [config](#test-config) and profile.
The script then compares the results with the expected results in `test_data/results/` by doing a selective `diff` (TODO).
Any differences will be reported (TODO).

### Test results

There are (at least) two scenarios when it can be helpful to run the [test script](#test-script):
1. practicing how to run the workflow
2. testing whether improvements to the workflow have broken existing functionality

In the latter case, it is possible that the improvements result in additional or different test results.
If this happens, then update `test/results.dvc` to capture the results that should be expected with the latest version of the workflow.

## Logs

All log files are output to one of the the following locations:
1. `logs/joblogs/{rule}`
2. `logs/chromium-preprocessing/{rule}`

Job logs are produced by the PBS Pro job scheduler when rules are submitted as jobs via the global profile under `profiles/global`.

Rule logs capture key outputs for each rule, redirected to a log file. 
Thes logs are stored under `logs/chromium-preprocessing` in a subdirectory based on the rule name.
