cite_seq_config=pep.config.cite_seq 

rule concat_hto_fastqs:
    input: hto=capturesheet("hto_fastqs")
    output: concat=Path(cite_seq_config.concat_dir, "{capture}")
    log:
        "logs/concat/{capture}"
    shell:
        """
            cat {input.hto}/*.R1*.fastq.gz > {output.concat}/R1.fastq.gz
            cat {input.hto}/*.R2*.fastq.gz > {output.concat}/R2.fastq.gz
        """