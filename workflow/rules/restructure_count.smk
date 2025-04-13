# This rule file contains rules that restructure the "outs" from 'cellranger count'
# By grouping related outputs across captures, the dataset becomes easier to navigate.
# Restructuring also allows users to selectively pull only the data of interest, reducing download times
# The new structure also makes it possible to specify dependencies more precisely, speeding up data validation.

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=out_dir/"summary/web/captures/{capture}.html"
    shell:
        """
        cp -v {input.tmp}/outs/metrics_summary.csv {output.metrics}
        cp -v {input.tmp}/outs/web_summary.html {output.web}
        """

# Restructure bam files
rule restructure_bams:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        ass_bam=out_dir/"bam/count/{capture}/assigned_alignments.bam",
        ass_bai=out_dir/"bam/count/{capture}/assigned_alignments.bam.bai"
    shell:
        """
        cp -v {input.tmp}/outs/possorted_genome_bam.bam {output.ass_bam}
        cp -v {input.tmp}/outs/possorted_genome_bam.bam.bai {output.ass_bai}
        """

# Restructure and recompress count matrices
rule restructure_counts:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        filtered_bc=out_dir/"count/filtered/{capture}/barcodes.tsv.gz",
        filtered_feat=out_dir/"count/filtered/{capture}/features.tsv.gz",
        filtered_mat=out_dir/"count/filtered/{capture}/matrix.mtx.gz",
        raw_bc=out_dir/"count/raw/{capture}/barcodes.tsv.gz",
        raw_feat=out_dir/"count/raw/{capture}/features.tsv.gz",
        raw_mat=out_dir/"count/raw/{capture}/matrix.mtx.gz"
    shell:
        """
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/barcodes.tsv.gz | gzip -n > {output.filtered_bc}
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/features.tsv.gz | gzip -n > {output.filtered_feat}
        zcat {input.tmp}/outs/filtered_feature_bc_matrix/matrix.mtx.gz   | gzip -n > {output.filtered_mat}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/barcodes.tsv.gz | gzip -n > {output.raw_bc}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/features.tsv.gz | gzip -n > {output.raw_feat}
        zcat {input.tmp}/outs/raw_feature_bc_matrix/matrix.mtx.gz   | gzip -n > {output.raw_mat}
        """

# Restructure h5 data
rule restructure_h5:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        mol=out_dir/"h5/{capture}/molecule_info.h5",
        raw=out_dir/"h5/{capture}/raw_feature_bc_matrix.h5",
        filtered=out_dir/"h5/{capture}/filtered_feature_bc_matrix.h5"
    shell:
        """
        cp -v {input.tmp}/outs/molecule_info.h5 {output.mol}
        cp -v {input.tmp}/outs/raw_feature_bc_matrix.h5 {output.raw}
        cp -v {input.tmp}/outs/filtered_feature_bc_matrix.h5 {output.filtered}
        """

# Restructure analysis results
rule restructure_analysis:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        dir=directory(out_dir/"cr_analysis/captures/{capture}")
    shell:
        """
        cp -v -r {input.tmp}/outs/analysis {output.dir}
        """

# Restructure loupe files
rule restructure_loupe:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        filtered=out_dir/"loupe/count/filtered/{capture}.cloupe"
    shell:
        """
        cp -v {input.tmp}/outs/cloupe.cloupe {output.filtered}
        """