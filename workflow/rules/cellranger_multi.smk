# This smk file contains rules for running 'cellranger multi' on multiple captures

# Extend targets
targets.extend([out_dir/"summary/metrics/cr_summary.csv"])
if 'vdj' in assays:
    targets.extend(
        expand(
            out_dir/"loupe/vdj/{capture}.vloupe,
            capture=captures.index
        )
    )

# 'cellranger multi' requires a 'multi config CSV' file
# Rather than hand-craft a CSV file for each individual capture, this workflow creates a
# CSV file for each capture dynamically, based on the global configuration


# Create CSV section of multi config
# Select rows where 'fastq_id' matches {capture}
# Convert relative paths to absolute paths because cellranger can't handle relative paths
rule select_libraries:
    input:
        csv=config['deps']['libraries']
    output:
        csv=temp(out_dir/"csv/{capture}/libraries.csv")
    run:
        import pandas as pd
        import os
        df = pd.read_csv(input.csv)
        filtered_df = df[df["fastq_id"] == wildcards.capture].copy()
        filtered_df["fastqs"] = filtered_df["fastqs"].apply(
            lambda x: os.path.join(os.getcwd(), x)
        )
        filtered_df.to_csv(output.csv, index=False)
 

# Create INI section of multi config
rule create_ini:
    output:
        ini=temp(out_dir/"csv/config.ini")
    run:
        import os
        with open(output.ini, "w") as f:
            for assay, ref_path in config["ref"].items():
                # Compare to list of assays found in libraries.csv
                if assay in assays:
                    # Convert to absolute path because cellranger multi can't handle relative paths
                    abs_path = os.path.abspath(ref_path)
                    f.write("[{}]\n".format(assay))
                    f.write("reference,{}\n".format(abs_path))
                    if assay in config["params"].keys():
                        for key, value in config["params"][assay].items():
                            f.write("{},{}\n".format(key,value))
                    f.write("\n")

# Combine INI section with libraries section
rule combine_dynamic_config:
    input:
        csv=rules.select_libraries.output.csv,
        ini=rules.create_ini.output.ini
    output:
        conf=out_dir/"csv/{capture}/multi_config.csv"
    shell:
        """
        cat {input.ini} > {output.conf}
        echo "[libraries]" >> {output.conf}
        cat {input.csv} >> {output.conf}
        """

rule cellranger_multi:
    input:
        conf=rules.combine_dynamic_config.output.conf
    output:
        cr_dir=temp(directory(out_dir/"tmp/{capture}"))
    envmodules:
        "cellranger/9.0.1"
    log:
        "logs/chromium-preprocessing/cellranger_multi/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.cr_dir}
        PATH=$PWD/profiles/global/nci_a56/resources/:$PATH \
        cellranger multi \
            --output-dir {output.cr_dir} \
            --id {wildcards.capture} \
            --csv {input.conf} \
            --jobmode={resources.jobmode} \
            --maxjobs {resources.maxjobs} \
            --jobinterval {resources.jobinterval} \
            --mempercore {resources.mempercore} \
            > {log} 2>&1
        rm -rf {output.cr_dir}/SC_MULTI_CS
        """

# Restructure non-VDJ outputs
rule restructure_outs:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        filtered=directory(out_dir/"count/filtered_feature_bc_matrix/{capture}"),
        raw=directory(out_dir/"count/raw_feature_bc_matrix/{capture}"),
        bams=directory(out_dir/"bam/count/{capture}"),
        h5=directory(out_dir/"h5/{capture}"),
        loupe=directory(out_dir/"loupe/count/{capture}"),
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=out_dir/"summary/web/{capture}.html"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}
        # Summary files
        cp -v $sample_dir/metrics_summary.csv {output.metrics}
        cp -v $sample_dir/web_summary.html {output.web}
        # Bams
        mkdir -p {output.bams}
        cp -v $out_dir/count/unassigned_alignments.bam* {output.bams}/
        cp -v $sample_dir/count/sample_alignments.bam* {output.bams}/
        # Count matrices
        mkdir -p {output.filtered} {output.raw}
        for file in $sample_dir/count/sample_filtered_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.filtered}/$filename
        done
        for file in $out_dir/count/raw_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.raw}/$filename
        done
        # h5
        mkdir -p {output.h5}
        cp -v $sample_dir/count/*.h5 {output.h5}/
        cp -v $out_dir/count/*.h5 {output.h5}/
        # Loupe
        mkdir -p {output.loupe}
        cp -v $out_dir/count/raw_cloupe.cloupe {output.loupe}/
        cp -v $sample_dir/count/sample_cloupe.cloupe {output.loupe}/
        """

if "vdj" in assays:
    rule restructure_vdj_outs:
        input:
            tmp=rules.cellranger_multi.output.cr_dir
        output:
            vdj_t=directory(out_dir/"vdj_t/{capture}"),
            bams=directory(out_dir/"bam/vdj/{capture}"),
            loupe=directory(out_dir/"loupe/vdj/{capture}")
        shell:
            """
            # Source directories
            out_dir={input.tmp}/outs/multi
            sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}
            # Bams
            mkdir -p {output.bams}
            cp -v $out_dir/vdj_t/all_contig.bam* {output.bams}/
            cp -v $sample_dir/vdj_t/consensus.bam* {output.bams}/
            # Loupe
            mkdir -p {output.loupe}
            cp -v $sample_dir/vdj_t/vloupe.vloupe {output.loupe}/
            # VDJ
            mkdir -p {output.vdj_t}/raw {output.vdj_t}/filtered
            cp -v -r $out_dir/vdj_t {output.vdj_t}/raw 
            cp -v -r $sample_dir/vdj_t {output.vdj_t}/filtered
            """

