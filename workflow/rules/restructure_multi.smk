# This rule file contains rules that restructure the "outs" from 'cellranger count'
# By grouping related outputs across captures, the dataset becomes easier to navigate.
# Restructuring also allows users to selectively pull only the data of interest, reducing download times
# The new structure also makes it possible to specify dependencies more precisely, speeding up data validation.

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=report_dir/"web/captures/{capture}.html"
    shell:
        """
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}
        cp -v $sample_dir/metrics_summary.csv {output.metrics}
        cp -v $sample_dir/web_summary.html {output.web}
        """

# Restructure bam files
rule restructure_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        ass_bam=out_dir/"bam/count/captures/{capture}/assigned_alignments.bam",
        ass_bai=out_dir/"bam/count/captures/{capture}/assigned_alignments.bam.bai",
        unass_bam=out_dir/"bam/count/captures/{capture}/unassigned_alignments.bam",
        unass_bai=out_dir/"bam/count/captures/{capture}/unassigned_alignments.bam.bai"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count
        # Bams
        mkdir -p $(dirname {output.ass_bam})
        cp -v $out_dir/unassigned_alignments.bam {output.unass_bam}
        cp -v $out_dir/unassigned_alignments.bam.bai {output.unass_bai}
        cp -v $sample_dir/sample_alignments.bam {output.ass_bam}
        cp -v $sample_dir/sample_alignments.bam.bai {output.ass_bai}
        """

# Restructure count matrices (recompressing to remove timestamps)
rule restructure_counts:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        filtered_bc=out_dir/"count/filtered/{capture}/barcodes.tsv.gz",
        filtered_feat=out_dir/"count/filtered/{capture}/features.tsv.gz",
        filtered_mat=out_dir/"count/filtered/{capture}/matrix.mtx.gz",
        raw_bc=out_dir/"count/raw/{capture}/barcodes.tsv.gz",
        raw_feat=out_dir/"count/raw/{capture}/features.tsv.gz",
        raw_mat=out_dir/"count/raw/{capture}/matrix.mtx.gz"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count/raw_feature_bc_matrix
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/sample_filtered_feature_bc_matrix
        # Copy and recompress
        zcat $sample_dir/barcodes.tsv.gz | gzip -n > {output.filtered_bc}
        zcat $sample_dir/features.tsv.gz | gzip -n > {output.filtered_feat}
        zcat $sample_dir/matrix.mtx.gz | gzip -n > {output.filtered_mat}
        zcat $out_dir/barcodes.tsv.gz | gzip -n > {output.raw_bc}
        zcat $out_dir/features.tsv.gz | gzip -n > {output.raw_feat}
        zcat $out_dir/matrix.mtx.gz | gzip -n > {output.raw_mat}
        """

# Restructure and rename h5 files
rule restructure_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_mat=out_dir/"h5/captures/{capture}/raw_feature_bc_matrix.h5",
        raw_mol=out_dir/"h5/captures/{capture}/raw_molecule_info.h5",
        filtered_mat=out_dir/"h5/captures/{capture}/feature_bc_matrix.h5",
        filtered_mol=out_dir/"h5/captures/{capture}/molecule_info.h5"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count
        # h5
        cp -v $out_dir/raw_feature_bc_matrix.h5 {output.raw_mat}
        cp -v $out_dir/raw_molecule_info.h5 {output.raw_mol}
        cp -v $sample_dir/sample_filtered_feature_bc_matrix.h5 {output.filtered_mat}
        cp -v $sample_dir/sample_molecule_info.h5 {output.filtered_mol}
        """

# Restructure non-VDJ loupe files
rule restructure_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw=out_dir/"loupe/count/raw/{capture}.cloupe",
        filtered=out_dir/"loupe/count/filtered/{capture}.cloupe"
    shell:
        """
        cp -v {input.tmp}/outs/multi/count/raw_cloupe.cloupe {output.raw}
        cp -v {input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/sample_cloupe.cloupe {output.filtered}
        """

rule restructure_vdj_fa:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_contig_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fasta",
        raw_contig_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fasta.fai",
        raw_contig_fq=out_dir/"vdj/{vdj_assay}/fa/{capture}/all_contig.fastq",
        filtered_contig_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/filtered_contig.fasta",
        filtered_contig_fq=out_dir/"vdj/{vdj_assay}/fa/{capture}/filtered_contig.fastq",
        ref_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/concat_ref.fasta",
        ref_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/concat_ref.fasta.fai",
        consensus_fa=out_dir/"vdj/{vdj_assay}/fa/{capture}/consensus.fasta",
        consensus_fai=out_dir/"vdj/{vdj_assay}/fa/{capture}/consensus.fasta.fai",
        donor=out_dir/"vdj/{vdj_assay}/fa/{capture}/donor_regions.fa"
    shell:
        """
        # Base directories
        multi={input.tmp}/outs/multi/{wildcards.vdj_assay}
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.capture}/{wildcards.vdj_assay}
        # Copy results
        cp -v $multi/all_contig.fasta {output.raw_contig_fa}
        cp -v $multi/all_contig.fasta.fai {output.raw_contig_fai}
        cp -v $multi/all_contig.fastq {output.raw_contig_fq}
        cp -v $per_sample/filtered_contig.fasta {output.filtered_contig_fa}
        cp -v $per_sample/filtered_contig.fastq {output.filtered_contig_fq}
        cp -v $per_sample/concat_ref.fasta {output.ref_fa}
        cp -v $per_sample/concat_ref.fasta.fai {output.ref_fai}
        cp -v $per_sample/consensus.fasta {output.consensus_fa}
        cp -v $per_sample/consensus.fasta.fai {output.consensus_fai}
        cp -v $per_sample/donor_regions.fa {output.donor}
        """

rule restructure_vdj_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam",
        raw_bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam.bai",
        filtered_bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/consensus.bam",
        filtered_bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/consensus.bam.bai"
    shell:
        """
        # Source directories
        multi={input.tmp}/outs/multi
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.capture}
        # Bams
        cp -v $multi/{wildcards.vdj_assay}/all_contig.bam {output.raw_bam}
        cp -v $multi/{wildcards.vdj_assay}/all_contig.bam.bai {output.raw_bai}
        cp -v $per_sample/{wildcards.vdj_assay}/consensus.bam {output.filtered_bam}
        cp -v $per_sample/{wildcards.vdj_assay}/consensus.bam.bai {output.filtered_bai}
        """

rule restructure_vdj_annotations:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        all_bed=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.bed",
        all_csv=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.csv",
        all_json=out_dir/"vdj/{vdj_assay}/annotations/{capture}/all_contigs.json",
        consensus=out_dir/"vdj/{vdj_assay}/annotations/{capture}/consensus.csv",
        filtered=out_dir/"vdj/{vdj_assay}/annotations/{capture}/filtered_contigs.csv"
    shell:
        """
        # Source directories
        multi={input.tmp}/outs/multi/{wildcards.vdj_assay}
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.capture}/{wildcards.vdj_assay}
        # Annotations
        cp -v $multi/all_contig_annotations.bed {output.all_bed}
        cp -v $multi/all_contig_annotations.csv {output.all_csv}
        cp -v $multi/all_contig_annotations.json {output.all_json}
        cp -v $per_sample/consensus_annotations.csv {output.consensus}
        cp -v $per_sample/filtered_contig_annotations.csv {output.filtered}
        """

rule restructure_vdj_results:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        airr=out_dir/"vdj/{vdj_assay}/results/{capture}/airr_rearrangement.tsv",
        bc=out_dir/"vdj/{vdj_assay}/results/{capture}/cell_barcodes.json",
        clono=out_dir/"vdj/{vdj_assay}/results/{capture}/clonotypes.csv",
        pb=out_dir/"vdj/{vdj_assay}/results/{capture}/vdj_contig_info.pb"
    shell:
        """
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.capture}/{wildcards.vdj_assay}
        cp -v $per_sample/airr_rearrangement.tsv {output.airr}
        cp -v $per_sample/cell_barcodes.json {output.bc}
        cp -v $per_sample/clonotypes.csv {output.clono}
        cp -v $per_sample/vdj_contig_info.pb {output.pb}
        """

rule restructure_vdj_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        loupe=out_dir/"loupe/{vdj_assay}/{capture}.vloupe"
    shell:
        """
        cp -v {input.tmp}/outs/per_sample_outs/{wildcards.capture}/{wildcards.vdj_assay}/vloupe.vloupe {output.loupe}
        """

# Restructure analysis results
rule restructure_analysis:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        dir=directory(out_dir/"cr_analysis/captures/{capture}")
    shell:
        """
        cp -v -r {input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/analysis {output.dir}
        """