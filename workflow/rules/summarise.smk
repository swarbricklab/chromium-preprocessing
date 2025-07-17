# This rule file includes for reorganising and summarising the output from multi or count

rule cr_summarise:
    input:
        individual_summaries=expand(
            out_dir/"summary/metrics/{capture}.csv", 
            capture=captures.index
        ),
        captures_config=config["deps"]["captures"]
    output:
        group_summary=temp(out_dir/"summary/metrics/cr_summary.csv")
    params:
        groups=','.join(captures.index)
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            # Stack the individual summaries with capture names
            csvstack --group-name capture --groups {params.groups} {input.individual_summaries} \
                > temp_stacked.csv
            
            # Use csvjoin to add pool information from captures config
            csvjoin --no-inference -c capture temp_stacked.csv {input.captures_config} \
                > temp_joined.csv
            
            # Capitalize all column headers
            sed '1s/\\b\\w/\\U&/g' temp_joined.csv > {output.group_summary}
            
            # Clean up temp files
            rm temp_stacked.csv temp_joined.csv
        """