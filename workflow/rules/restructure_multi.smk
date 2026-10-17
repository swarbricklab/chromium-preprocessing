# This rule file contains rules that restructure the "outs" from 'cellranger multi'
# By grouping related outputs across captures, the dataset becomes easier to navigate.
# Restructuring also allows users to selectively pull only the data of interest, reducing download times
# The new structure also makes it possible to specify dependencies more precisely, speeding up data validation.

# Verbatim-copy rules hardlink their outputs (see lc/lcr in common.smk) instead of copying,
# so they are pure filesystem metadata and run on the controller rather than queuing a PBS
# job each. Only the count-matrix recompress (restructure_counts, strips gzip timestamps for
# determinism), the path-stripping summary, and the BAM normalisation (restructure_vdj_bams,
# samtools) stay as compute/cluster rules.
localrules:
    restructure_summary,
    restructure_bams,
    restructure_raw_h5,
    restructure_h5,
    restructure_loupe,
    restructure_vdj_fa,
    restructure_vdj_annotations,
    restructure_vdj_results,
    restructure_vdj_loupe,
    restructure_analysis,

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=report_dir/"cellranger/web_summaries/captures/{capture}.html"
    shell:
        """
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}
        cp -v $sample_dir/metrics_summary.csv {output.metrics}
        cp -v $sample_dir/web_summary.html {output.web}
        # Strip the embedded absolute workspace paths so web_summary.html is deterministic
        # and portable (see issue #137).
        sed -i "s|$(pwd)/||g" {output.web}
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
        lc $out_dir/unassigned_alignments.bam {output.unass_bam}
        lc $out_dir/unassigned_alignments.bam.bai {output.unass_bai}
        lc $sample_dir/sample_alignments.bam {output.ass_bam}
        lc $sample_dir/sample_alignments.bam.bai {output.ass_bai}
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
rule restructure_raw_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_mat=out_dir/"h5/captures/{capture}/raw_feature_bc_matrix.h5",
        raw_mol=out_dir/"h5/captures/{capture}/raw_molecule_info.h5"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        # h5
        lc $out_dir/raw_feature_bc_matrix.h5 {output.raw_mat}
        lc $out_dir/raw_molecule_info.h5 {output.raw_mol}
        """

# Restructure and rename h5 files
rule restructure_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        mat=out_dir/"h5/captures/{capture}/feature_bc_matrix.h5",
        mol=out_dir/"h5/captures/{capture}/molecule_info.h5"
    shell:
        """
        # Source directories
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count
        # h5
        lc $sample_dir/sample_filtered_feature_bc_matrix.h5 {output.mat}
        lc $sample_dir/sample_molecule_info.h5 {output.mol}
        """

# Restructure non-VDJ loupe files
rule restructure_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw=out_dir/"loupe/count/raw/{capture}.cloupe",
        cloupe=out_dir/"loupe/count/filtered/{capture}.cloupe"
    shell:
        """
        lc {input.tmp}/outs/multi/count/raw_cloupe.cloupe {output.raw}
        lc {input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/sample_cloupe.cloupe {output.cloupe}
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
        lc $multi/all_contig.fasta {output.raw_contig_fa}
        lc $multi/all_contig.fasta.fai {output.raw_contig_fai}
        lc $multi/all_contig.fastq {output.raw_contig_fq}
        lc $per_sample/filtered_contig.fasta {output.filtered_contig_fa}
        lc $per_sample/filtered_contig.fastq {output.filtered_contig_fq}
        lc $per_sample/concat_ref.fasta {output.ref_fa}
        lc $per_sample/concat_ref.fasta.fai {output.ref_fai}
        lc $per_sample/consensus.fasta {output.consensus_fa}
        lc $per_sample/consensus.fasta.fai {output.consensus_fai}
        lc $per_sample/donor_regions.fa {output.donor}
        """

rule restructure_vdj_bams:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam",
        raw_bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/all_contig.bam.bai",
        filtered_bam=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/consensus.bam",
        filtered_bai=out_dir/"bam/vdj/{vdj_assay}/captures/{capture}/consensus.bam.bai"
    container:
        "docker://quay.io/biocontainers/samtools:1.22--h96c455f_0"
    shell:
        # Cell Ranger's VDJ contig BAMs assemble the same contigs/reads each run but are
        # emitted in a run-varying record order, and their @PG carries a run-unique martian
        # path. Normalise to a deterministic BAM so reruns are byte-identical and can be
        # compared against the golden (see issue #137): canonical single-thread coordinate
        # sort (--no-PG), strip the @PG header lines, and re-index. The contig set (@SQ) and
        # read content are unchanged.
        """
        multi={input.tmp}/outs/multi
        per_sample={input.tmp}/outs/per_sample_outs/{wildcards.capture}

        normalise() {{
            src="$1"; dst="$2"
            samtools sort -@ 1 --no-PG "$src" -o "$dst.presort.bam"
            samtools view -H "$dst.presort.bam" | grep -v '^@PG' > "$dst.hdr.sam"
            samtools reheader --no-PG "$dst.hdr.sam" "$dst.presort.bam" > "$dst"
            samtools index "$dst"
            rm -f "$dst.presort.bam" "$dst.hdr.sam"
        }}

        normalise $multi/{wildcards.vdj_assay}/all_contig.bam {output.raw_bam}
        normalise $per_sample/{wildcards.vdj_assay}/consensus.bam {output.filtered_bam}
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
        lc $multi/all_contig_annotations.bed {output.all_bed}
        lc $multi/all_contig_annotations.csv {output.all_csv}
        lc $multi/all_contig_annotations.json {output.all_json}
        lc $per_sample/consensus_annotations.csv {output.consensus}
        lc $per_sample/filtered_contig_annotations.csv {output.filtered}
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
        lc $per_sample/airr_rearrangement.tsv {output.airr}
        lc $per_sample/cell_barcodes.json {output.bc}
        lc $per_sample/clonotypes.csv {output.clono}
        lc $per_sample/vdj_contig_info.pb {output.pb}
        """

rule restructure_vdj_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        loupe=out_dir/"loupe/{vdj_assay}/{capture}.vloupe"
    shell:
        """
        lc {input.tmp}/outs/per_sample_outs/{wildcards.capture}/{wildcards.vdj_assay}/vloupe.vloupe {output.loupe}
        """

# Restructure analysis results
rule restructure_analysis:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        dir=directory(out_dir/"cr_analysis/captures/{capture}")
    shell:
        """
        lcr {input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/analysis {output.dir}
        """