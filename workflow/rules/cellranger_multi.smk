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

# Restructure summary data
rule restructure_summary:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        metrics=out_dir/"summary/metrics/{capture}.csv",
        web=out_dir/"summary/web/{capture}.html"
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
        ass_bam=out_dir/"bam/count/{capture}/assigned_alignments.bam",
        ass_bai=out_dir/"bam/count/{capture}/assigned_alignments.bam.bai",
        unass_bam=out_dir/"bam/count/{capture}/unassigned_alignments.bam",
        unass_bai=out_dir/"bam/count/{capture}/unassigned_alignments.bam.bai"
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
        filtered=directory(out_dir/"count/filtered_feature_bc_matrix/{capture}"),
        raw=directory(out_dir/"count/raw_feature_bc_matrix/{capture}")
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count
        # Count matrices
        mkdir -p {output.filtered} {output.raw}
        for file in $sample_dir/sample_filtered_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.filtered}/$filename
        done
        for file in $out_dir/raw_feature_bc_matrix/*.gz; do
            echo "Recompressing $file"
            filename=$(basename $file)
            zcat $file | gzip -n > {output.raw}/$filename
        done
        """
# Restructure and rename h5 files
rule restructure_h5:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw_mat=out_dir/"h5/raw/{capture}/feature_bc_matrix.h5",
        raw_mol=out_dir/"h5/raw/{capture}/molecule_info.h5",
        filtered_mat=out_dir/"h5/filtered/{capture}/feature_bc_matrix.h5",
        filtered_mol=out_dir/"h5/filtered/{capture}/molecule_info.h5"
    shell:
        """
        # Source directories
        out_dir={input.tmp}/outs/multi/count
        sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}/count
        # h5
        cp -v $out_dir/sample_filtered_feature_bc_matrix.h5 {output.raw_mat}
        cp -v $out_dir/sample_molecule_info.h5 {output.raw_mol}
        cp -v $sample_dir/sample_filtered_feature_bc_matrix.h5 {output.filtered_mat}
        cp -v $sample_dir/sample_molecule_info.h5 {output.filtered_mol}
        """

# Restructure non-VDJ loupe files
rule restructure_loupe:
    input:
        tmp=rules.cellranger_multi.output.cr_dir
    output:
        raw=out_dir/"loupe/count/raw/{capture}.cloupe",
        filtered=out_dir/"loupe/count/filtered/{capture}.cloupe/"
    shell:
        """
        cp -v {input.tmp}/outs/multi/count/raw_cloupe.cloupe {output.raw}
        cp -v {input.tmp}/outs/per_sample_outs/{wildcards.capture}/count/sample_cloupe.cloupe {output.filtered}
        """

if "vdj" in assays:
    rule restructure_vdj_outs:
        input:
            tmp=rules.cellranger_multi.output.cr_dir
        output:
            vdj_t=directory(out_dir/"vdj_t/{capture}"),
            raw_bam=out_dir/"bam/vdj/{capture}/all_contig.bam",
            raw_bai=out_dir/"bam/vdj/{capture}/all_contig.bam.bai",
            filtered_bam=out_dir/"bam/vdj/{capture}/consensus.bam",
            filtered_bai=out_dir/"bam/vdj/{capture}/consensus.bam.bai",
            loupe=out_dir/"loupe/vdj/{capture}.vloupe"
        shell:
            """
            # Source directories
            out_dir={input.tmp}/outs/multi
            sample_dir={input.tmp}/outs/per_sample_outs/{wildcards.capture}
            # Bams
            mkdir -p {output.bams}
            cp -v $out_dir/vdj_t/all_contig.bam {output.raw_bam}
            cp -v $out_dir/vdj_t/all_contig.bam.bai {output.raw_bai}
            cp -v $sample_dir/vdj_t/consensus.bam {output.filtered_bam}
            cp -v $sample_dir/vdj_t/consensus.bam.bai {output.filtered_bai}
            # Loupe
            mkdir -p {output.loupe}
            cp -v $sample_dir/vdj_t/vloupe.vloupe {output.loupe}
            # VDJ
            mkdir -p {output.vdj_t}/raw {output.vdj_t}/filtered
            cp -v -r $out_dir/vdj_t {output.vdj_t}/raw 
            cp -v -r $sample_dir/vdj_t {output.vdj_t}/filtered
            """

