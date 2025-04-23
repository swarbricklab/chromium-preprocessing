# This smk file contains rules for running 'cellranger multi' on multiple captures

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
        conf=temp(out_dir/"csv/{capture}/multi_config.csv")
    shell:
        """
        cat {input.ini} > {output.conf}
        echo "[libraries]" >> {output.conf}
        cat {input.csv} >> {output.conf}
        """

# Run cellranger multi with dynamically generated config
rule cellranger_multi:
    input:
        conf=rules.combine_dynamic_config.output.conf
    output:
        cr_dir=temp(directory(out_dir/"tmp/{capture}"))
    envmodules:
        "cellranger/9.0.1",
        "qsub/ext"
    log:
        "logs/chromium-preprocessing/cellranger_multi/{capture}.log"
    shell:
        """
        # Snakemake creates output directory but cellranger complains if directory alrady exists!
        rm -rf {output.cr_dir}
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

