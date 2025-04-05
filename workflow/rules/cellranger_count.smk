# This rule file contains rules for running cellranger count
# We prefer count over multi when only gene expression libraries are being processed.

# Extend targets
targets.extend([out_dir/"summary/metrics/cr_summary.csv"])

rule cellranger_count:
    input:
        fastqs=get_fastqs,
        transcriptome=config['ref']['gene-expression']
    output:
        cr_dir=temp(directory(out_dir/"tmp/{capture}"))
    params:
        count_options=get_count_options
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_count/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.cr_dir}

        cellranger count \
            --output-dir {output.cr_dir} \
            --id={wildcards.capture} \
            --sample={wildcards.capture} \
            --fastqs={input.fastqs} \
            --transcriptome={input.transcriptome} \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            {params.count_options} \
            > {log} 2>&1
        rm -rf {output.cr_dir}/SC_RNA_COUNTER_CS
        """

# Restructure outputs
rule restructure_outs:
    input:
        tmp=rules.cellranger_count.output.cr_dir
    output:
        filtered=directory(out_dir/"count/filtered_feature_bc_matrix/{capture}"),
        raw=directory(out_dir/"count/raw_feature_bc_matrix/{capture}"),
        bams=directory(out_dir/"bam/{capture}"),
        h5=directory(out_dir/"h5/{capture}"),
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=out_dir/"summary/web/{capture}.html"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/
        # Summary files
        cp -v $out_dir/metrics_summary.csv {output.metrics}
        cp -v $out_dir/web_summary.html {output.web}
        # Bams
        mkdir -p {output.bams}
        cp -v $out_dir/possorted_genome_bam.bam* {output.bams}/
        # Count matrices
        mkdir -p {output.filtered} {output.raw}
        # Decompress and recompress to remove timestamps
        for file in $out_dir/filtered_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.filtered}/$filename
        done
        for file in $out_dir/raw_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.raw}/$filename
        done
        # h5
        mkdir -p {output.h5}
        cp -v $out_dir/*.h5 {output.h5}/
        """

