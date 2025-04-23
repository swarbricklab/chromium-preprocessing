# Configuration Guide

## Config

The main config file for this workflow defines the dependencies, outputs and parameters used in this workflow, as well as the reference files used with the workflow, including reference genomes, probe sets, etc.

The config file is normally named `config.yaml` and is normally organised under `config/chromium-preprocessing` in the dataset repo.

### Templates

Within this repo, template config files are provided under [config/templates](templates/).
There are two template files, as follows:
- [config/templates/count/config.yaml](templates/count/config.yaml) -- for when only gene expression libraries are to be processed
- [config/templates/multi/config.yaml](templates/multi/config.yaml) -- for when feature barcode (CITE/ADT/HTO) and/or VDJ libraries are also present

Copy the appropriate template to `config/chromium-preprocessing/config.yaml` in the dataset repo and edit as appropriate.
Generally, most of the options in the template can be left unchanged, but review each item to ensure that it matches the needs of your dataset.

### Tests

Config files for running this workflow are also available under [config/tests](tests/) in this repo.
This config files are used in conjunction with the [run_tests.sh](../run_test.sh) script.

### Config content

The config file is divided into four blocks, as follows:
- deps
- refs
- outs
- params

The function of each block is described below.
See the comments within the templates for the details of each item.

#### deps

This block lists data dependencies for the workflow, including the paths to
- raw data
- [samplesheets](#samplesheets)

#### refs

This block lists paths to reference data used by the workflow, such as transcriptome and VDJ references.
At present, gene expression data is always required and so `refs.gene-expression` is a required item.
References for other assays (modalities) such as feature barcodes and VDJ are only required when libraries for those assays are specified in the [libraries](#libraries-librariescsv) samplesheet.

> Note 1: while transcriptome and VDJ references can be downloaded from the 10X website or imported from our [references](https://github.com/swarbricklab/references) registry, [feature references](https://www.10xgenomics.com/support/software/cell-ranger/latest/analysis/inputs/cr-feature-ref-csv) for CITE/ADT/HTO are dependent on which feature barcodes are used in the experiment, and so need to be created manually.
 
> Note 2: both VDJ-B and VDJ-T share the same reference

#### outs

The `outs` block defines paths to the outputs produced by this workflow:
- results: the root directory for all result data
- logs: the root directory for log files

#### params

The `params` block defines non-path parameters for tuning the behaviour of the workflow.
The structure of this block varies depends on which assays are present and which optional "extras" are enabled.
Only the `gene-expression` sub-block is required.

The following sub-blocks can be specified:
- [extras](#extras)
- [gene-expression](#extras)
- [feature](#feature)
- [vdj](#vdj)
- [aggr](#aggr)
- [annotate](#annotate) (not yet supported)
- [hto](#hto) (not yet supported)

A summary of each sub-block is given below.
See the comments in the templates for details of each item.

##### extras

The `extras` sub-block defines which of the following optional `cellranger` features should be used.
- [aggr](#aggr): use `cellranger aggr` to aggregate split pools
- [annotate](#annotate): use 10X Cloud for automated cell-type annotations (not yet supported)
- [hto](#hto): use hashtag oligos for HTO demux (not yet supported)

The detailed specifications for each "extra" option are made in separate blocks for each option.
See the links above for details.

> Note: use boolean `true`/`false` (unquoted) to turn these options on or off.
> Options which are not used can either be set to `false` or deleted.

##### gene-expression

The `gene-expression` block defines options for processing gene expression (RNA) libraries with either `cellranger count` or `cellranger multi`.
If only gene expression libraries are present in the [libraries](#libraries-librariescsv) samplesheet, then the workflow will use `cellranger count` and the options specified here will be passed in as command line options or flags.
If other libraries (such as feature barcodes or VDJ) are also present in the [libraries](#libraries-librariescsv) samplesheet, then the workflow will use `cellranger multi` and the options specified here will be used to dynamically generate the `[gene-expression]` section of a [multi config CSV](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) file.

See the [10X documentation](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) for the available options and their meanings.

> Note 1: the `reference` item is already covered by `refs.gene-expression` in [refs](#refs) above and should not be specified here.

> Note 2: use boolean `true`/`false` (unquoted) for items that would be specified as `"true"` or `"false"` (quoted) in the [multi config CSV](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) file.

> Note 3: `cellranger count` uses "nosecondary" but this workflow follows `cellranger multi` by using "no-secondary" and converting internally.

##### feature

The `feature` block defines options for processing feature barcode (CITE/ADT/HTO) libraries with `cellranger multi`.
This section is only required if feature barcode libraries are present in the [libraries](#libraries-librariescsv) samplesheet AND additional items (such as `r1-length`) are specified.
If feature barcodes are not used or if feature barcodes can be processed with the default options (most cases) then this section should be deleted for clarity.

See the [10X documentation](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts#feature) for the options available and their meanings.

> Note: the `reference` item is already covered by `refs.feature` in [refs](#refs) above and should not be specified here.

##### vdj

The `vdj` block defines options for processing VDJ (VDJ-B/VDJ-T) libraries with `cellranger multi`.
This section is only required if VDJlibraries are present in the [libraries](#libraries-librariescsv) samplesheet AND additional items (such as `r1-length`) are specified.
If VDJ are not used or if feature barcodes can be processed with the default options (most cases) then this section should be deleted for clarity.

See the [10X documentation](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts#vdj) for the options available and their meanings.

> Note 1: the `reference` item is already covered by `refs.vdj` in [refs](#refs) above and should not be specified here.

> Note 2: both VDJ-B and VDJ-T share the same reference

##### aggr

The `aggr` block defines options for aggregating split pools with `cellranger aggr`.
This block is only meaningful if `aggr: true` has been specified for `params.extras`, and should be deleted if aggregation is not used.
The options specified here are translated into CLI options for `cellranger aggr`.

See the [10X documentation](https://www.10xgenomics.com/support/software/cell-ranger/latest/resources/cr-command-line-arguments#aggr) for the options available and their meanings.

In particular, consider what value to specify for `normalize`:
- "mapped" (default): equalise read depth between the two captures to be aggregated
- "none": keep all reads in both captures

The default option ("mapped") minimises batch effects but throws away reads by downsampling the capture with greater read depth.
For "split captures" (derived from the same pool) batch effect should be minimal and so "none" is preferred.

> Note: `cellranger aggr` uses "nosecondary" but this workflow follows `cellranger multi` by using "no-secondary" and converting internally.

##### annotate

Not yet supported

##### hto

Not yet supported

## Samplesheets

This workflow requires the following two samplesheets, in addition to the config file:
1. [captures](#captures-capturescsv)
2. [libraries](#libraries-librariescsv)

These paths to these samplesheets are defined under `deps` in the config file above.

### Captures (`captures.csv`)

The "captures" samplesheet describes elements of the experimental design by defining the relationship between [captures](#capture), [pools](#pool) and [samples](#sample).

Create a CSV file with the following columns:
- [captures](#capture) (required)
- [pool](#pool)(required only if aggr is enabled)
- [sample](#sample) (required only if hto demux is enabled)

Additional columns may be freely added.
The column order is arbitrary.

The normal name for the samplesheet is `captures.csv`, and the normal location within a dataset repo is `config/chromium-preprocessing/config.yaml`.
These defaults are defined with the [template config files](#templates) but can be changed if needed.

#### capture

The `capture` column is a list of captures to be processed.
Each capture should only be listed once.
The captures should match [fastq_id](#fastq_id) in [libraries.csv](#libraries-librariescsv), except that the latter can contain duplicates.

#### pool

> The `pool` column is not required if aggregation is not enabled.
> Aggregation can be enabled by specifying `params.extras.aggr` in the main [configuration file](#config).

A pool of dissociated cells is sometimes split into two or more captures in order to capture more cells, and as an insurance against lane clogs in the Chromium machine.
The resulting count matrices, bam files and -- if applicable -- VDJ results from these "split captures" can be aggregated into pool-level results.

In order to aggregate split captures, specify the same value in the `pool` column for all captures to be aggregated. 

For captures that do need aggregation, either
1. leave the `pool` column empty
2. specify `NA` or `None` for the `pool` column
3. specify the same value for both the `capture` column and the `pool` column

Aggregation will be skipped in all of these cases.

In the following example, only captures `experiment1a` and `experiment1b` will be aggregated as `experiment1`.
The other captures will not be aggregated.

| capture      | pool        |
|--------------|-------------|
| experiment1a | experiment1 |
| experiment1b | experiment1 |
| experiment2  | experiment2 |
| experiment3  | NA          |
| experiment4  | None        |
| experiment5  |             |

#### sample

The `sample` column is a placeholder for HTO demux, which is not yet supported.

## Libraries (`libraries.csv`)

The libraries samplesheet is normally called `libraries.csv` and is normally organised under `config/chromium-preprocessing` in the dataset repo.
Samplesheets for running the workflow on test datasets are organised under [config/tests](tests) in this repo.

The libraries samplesheet modelled on the `[libraries]` section of the [CSV config](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) for `cellranger multi`.
See the linked docs for details, noting that the format of the "CSV" file provided to `cellranger` is technically INI rather than strictly CSV.

The difference betwen the libraries samplesheet and the `[libraries]` section of the [multi config CSV](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) file is that the former includes all libraries for all captures in the project, while the latter only specifies the libraries used in a single capture. 

> This workflow uses the information in the libraries samplesheet in conjunction with the [workflow config](#config) above to dynamically generate a [multi config CSV](https://www.10xgenomics.com/support/software/cell-ranger/latest/advanced/cr-multi-config-csv-opts) file for each capture.

All columns and values that can be specified for the `[libraries]` section can also be specified in the `libraries.csv` file used by this workflow, but only the following columns are required:
- [fastq_id](#fastq_id)
- [fastqs](#fastqs)
- [feature_types](#feature_types)

These columns have the same meanings as in the 10X documentation, but briefly ...

### fastq_id

The values in the `fastq_id` column correspond to the values in the `capture` column of the [captures](#captures-capturescsv) samplesheet above.
The fastq files in the directory specified in the [fastqs](#fastqs) column must start with this identifier.

#### fastqs

The `fastqs` column defines the path to a directory containing the fastq files for the assay (library type) specified in the [feature_types](#feature_types) column and the capture specified in the [fastq_id](#fastq_id) column.

#### feature_types

The `feature_types` column defines the assay (library) type for the fastq files specified in the [fastqs](#fastqs) column.
Note that only the following values have been tested:
- 'Gene Expression' (RNA)
- 'Antibody Capture' (CITE and/or HTO)
- 'VDJ-B' (BCR)
- 'VDJ-T' (TCR)

> Although `cellranger multi` can auto-detect VDJ-B versus VDJ-T if you just specify plain 'VDJ', this workflow requires that you explicitly indicate one or the other.
