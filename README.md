# Chromium Preprocessing

## Overview

Pre-processing for raw Chromium data, including GE (gene expression), FB (CITE) and VDJ, as well as basic QC.

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
If there is no consistent pattern, or if the pattern is difficult to capture, then it is often easier to just specify the paths manually in the capture sheet.