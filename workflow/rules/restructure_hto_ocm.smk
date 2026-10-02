# This rule file contains rules that restructure the "outs" from 'cellranger multi' with HTO or OCM demux enabled
# By grouping related outputs across captures, the dataset becomes easier to navigate.
# Restructuring also allows users to selectively pull only the data of interest, reducing download times
# The new structure also makes it possible to specify dependencies more precisely, speeding up data validation.

# These copy small metadata (summary csv/html, multiplexing analysis); run them
# on the controller rather than queuing a compute job. The bulk data copies
# (BAMs, h5, loupe, count matrices) remain compute jobs.
localrules:
    restructure_multiplexing_analysis,
    restructure_summary,

rule restructure_multiplexing_analysis:
    input: 
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        analysis=directory(out_dir/"multiplexing_analysis/{capture}")
    shell:
        """
        cp -v -r {input.tmp}/outs/multi/multiplexing_analysis {output.analysis}
        """

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}/{sample}.csv",
        web=report_dir/"web/samples/{capture}/{sample}.html"
    shell:
        """
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.sample}
        cp -v $sample_dir/metrics_summary.csv {output.metrics}
        cp -v $sample_dir/web_summary.html {output.web}
        """

# Restructure bam files for assigned alignments
rule restructure_assigned_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bam=out_dir/"bam/count/captures/{capture}/{sample}/assigned_alignments.bam",
        bai=out_dir/"bam/count/captures/{capture}/{sample}/assigned_alignments.bam.bai",
    shell:
        """
        # Source directory
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.sample}/count
        # Bams
        mkdir -p $(dirname {output.bam})
        cp -v $sample_dir/sample_alignments.bam {output.bam}
        cp -v $sample_dir/sample_alignments.bam.bai {output.bai}
        """

# Restructure bam files for unassigned alignments
rule restructure_unassigned_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bam=out_dir/"bam/count/captures/{capture}/unassigned_alignments.bam",
        bai=out_dir/"bam/count/captures/{capture}/unassigned_alignments.bam.bai"
    shell:
        """
        # Source directory
        out_dir={input.tmp}/outs/multi/count
        # Bams
        mkdir -p $(dirname {output.bam})
        cp -v $out_dir/unassigned_alignments.bam {output.bam}
        cp -v $out_dir/unassigned_alignments.bam.bai {output.bai}
        """

# Restructure raw count matrices (recompressing to remove timestamps)
rule restructure_raw_counts:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bc=out_dir/"count/raw/{capture}/barcodes.tsv.gz",
        feat=out_dir/"count/raw/{capture}/features.tsv.gz",
        mat=out_dir/"count/raw/{capture}/matrix.mtx.gz"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count/raw_feature_bc_matrix
        # Copy and recompress
        zcat $out_dir/barcodes.tsv.gz | gzip -n > {output.bc}
        zcat $out_dir/features.tsv.gz | gzip -n > {output.feat}
        zcat $out_dir/matrix.mtx.gz   | gzip -n > {output.mat}
        """

# Restructure sample count matrices (recompressing to remove timestamps)
rule restructure_sample_counts:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bc=out_dir/"count/filtered/{capture}/{sample}/barcodes.tsv.gz",
        feat=out_dir/"count/filtered/{capture}/{sample}/features.tsv.gz",
        mat=out_dir/"count/filtered/{capture}/{sample}/matrix.mtx.gz",
    shell:
        """
        # Source directory
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.sample}/count/sample_filtered_feature_bc_matrix
        # Copy and recompress
        zcat $sample_dir/barcodes.tsv.gz | gzip -n > {output.bc}
        zcat $sample_dir/features.tsv.gz | gzip -n > {output.feat}
        zcat $sample_dir/matrix.mtx.gz   | gzip -n > {output.mat}
        """

# Restructure and rename raw h5 files
rule restructure_raw_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        mat=out_dir/"h5/captures/{capture}/raw_feature_bc_matrix.h5",
        mol=out_dir/"h5/captures/{capture}/raw_molecule_info.h5"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        # h5
        cp -v $out_dir/raw_feature_bc_matrix.h5 {output.mat}
        cp -v $out_dir/raw_molecule_info.h5 {output.mol}
        """

# Restructure and rename sample h5 files
rule restructure_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        mat=out_dir/"h5/captures/{capture}/{sample}/feature_bc_matrix.h5",
        mol=out_dir/"h5/captures/{capture}/{sample}/molecule_info.h5"
    shell:
        """
        # Source directory
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.sample}/count
        # h5
        cp -v $sample_dir/sample_filtered_feature_bc_matrix.h5 {output.mat}
        cp -v $sample_dir/sample_molecule_info.h5 {output.mol}
        """

# Restructure raw non-VDJ loupe files
rule restructure_raw_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        cloupe=out_dir/"loupe/count/raw/{capture}.cloupe",
    shell:
        """
        cp -v {input.tmp}/outs/multi/count/raw_cloupe.cloupe {output.cloupe}
        """

# Restructure raw non-VDJ loupe files
rule restructure_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        cloupe=out_dir/"loupe/count/filtered/{capture}/{sample}.cloupe"
    shell:
        """
        cp -v {input.tmp}/outs/per_sample_outs/{wildcards.sample}/count/sample_cloupe.cloupe {output.cloupe}
        """

# -- vdj ---

rule restructure_raw_vdj_fa:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        contig_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fasta",
        contig_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fasta.fai",
        contig_fq=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fastq"
    shell:
        """
        # Base directory
        multi={input.tmp}/outs/multi/{wildcards.vdj_assay}
        # Copy results
        cp -v $multi/all_contig.fasta {output.contig_fa}
        cp -v $multi/all_contig.fasta.fai {output.contig_fai}
        cp -v $multi/all_contig.fastq {output.contig_fq}
        """

rule restructure_sample_vdj_fa:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        filtered_contig_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/filtered_contig.fasta",
        filtered_contig_fq=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/filtered_contig.fastq",
        ref_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/concat_ref.fasta",
        ref_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/concat_ref.fasta.fai",
        consensus_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/consensus.fasta",
        consensus_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/consensus.fasta.fai",
        donor=out_dir/"vdj/{vdj_assay}/fa/{capture}/{sample}/donor_regions.fa"
    shell:
        """
        # Base directory
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.sample}/{wildcards.vdj_assay}
        # Copy results
        cp -v $per_sample/filtered_contig.fasta {output.filtered_contig_fa}
        cp -v $per_sample/filtered_contig.fastq {output.filtered_contig_fq}
        cp -v $per_sample/concat_ref.fasta {output.ref_fa}
        cp -v $per_sample/concat_ref.fasta.fai {output.ref_fai}
        cp -v $per_sample/consensus.fasta {output.consensus_fa}
        cp -v $per_sample/consensus.fasta.fai {output.consensus_fai}
        cp -v $per_sample/donor_regions.fa {output.donor}
        """

rule restructure_raw_vdj_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam",
        bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam.bai",
    shell:
        """
        # Source directories
        multi={input.tmp}/outs/multi
        # Bams
        cp -v $multi/{wildcards.vdj_assay}/all_contig.bam {output.bam}
        cp -v $multi/{wildcards.vdj_assay}/all_contig.bam.bai {output.bai}
        """

rule restructure_sample_vdj_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/{sample}/consensus.bam",
        bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/{sample}/consensus.bam.bai"
    shell:
        """
        # Source directories
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.sample}
        # Bams
        cp -v $per_sample/{wildcards.vdj_assay}/consensus.bam {output.bam}
        cp -v $per_sample/{wildcards.vdj_assay}/consensus.bam.bai {output.bai}
        """

rule restructure_multi_vdj_annotations:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        bed=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.bed",
        csv=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.csv",
        json=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.json"
    shell:
        """
        # Source directory
        multi={input.tmp}/outs/multi/{wildcards.vdj_assay}
        # Annotations
        cp -v $multi/all_contig_annotations.bed {output.bed}
        cp -v $multi/all_contig_annotations.csv {output.csv}
        cp -v $multi/all_contig_annotations.json {output.json}
        """

rule restructure_sample_vdj_annotations:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        consensus=out_dir/"vdj/{vdj_assay}/annotations/{capture}/{sample}/consensus.csv",
        filtered=out_dir/"vdj/{vdj_assay}/annotations/{capture}/{sample}/filtered_contigs.csv"
    shell:
        """
        # Source directories
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.sample}/{wildcards.vdj_assay}
        # Annotations
        cp -v $per_sample/consensus_annotations.csv {output.consensus}
        cp -v $per_sample/filtered_contig_annotations.csv {output.filtered}
        """

rule restructure_vdj_results:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        airr=out_dir/"vdj/{vdj_assay}/results/{capture}/{sample}/airr_rearrangement.tsv",
        bc=out_dir/"vdj/{vdj_assay}/results/{capture}/{sample}/cell_barcodes.json",
        clono=out_dir/"vdj/{vdj_assay}/results/{capture}/{sample}/clonotypes.csv",
        pb=out_dir/"vdj/{vdj_assay}/results/{capture}/{sample}/vdj_contig_info.pb"
    shell:
        """
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.sample}/{wildcards.vdj_assay}
        cp -v $per_sample/airr_rearrangement.tsv {output.airr}
        cp -v $per_sample/cell_barcodes.json {output.bc}
        cp -v $per_sample/clonotypes.csv {output.clono}
        cp -v $per_sample/vdj_contig_info.pb {output.pb}
        """

rule restructure_vdj_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        loupe=out_dir/"loupe/{vdj_assay}/{capture}/{sample}.vloupe"
    shell:
        """
        cp -v {input.tmp}/outs/per_sample_outs/{wildcards.sample}/{wildcards.vdj_assay}/vloupe.vloupe {output.loupe}
        """

# Restructure analysis results
rule restructure_analysis:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        dir=directory(out_dir/"cr_analysis/captures/{capture}/{sample}")
    shell:
        """
        cp -v -r {input.tmp}/outs/per_sample_outs/{wildcards.sample}/count/analysis {output.dir}
        """
