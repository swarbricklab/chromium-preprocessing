# This rule file includes for reorganising and summarising the output from multi or count

# A quick csv stack/join; run on the controller rather than queuing a compute job.
localrules:
    cr_summarise,

# Helper functions to resolve per-capture vs per-sample metrics paths
def _is_demux():
    return config['params']['extras'].get('hto', False) or config['params']['extras'].get('ocm', False)

def get_summary_inputs(wildcards):
    if _is_demux():
        return expand(
            out_dir/"summary/metrics/{capture}/{sample}.csv",
            zip, capture=captures['capture'], sample=captures['sample']
        )
    else:
        return expand(
            out_dir/"summary/metrics/{capture}.csv",
            capture=captures.index
        )

def get_summary_groups():
    if _is_demux():
        return ','.join(captures['sample'])
    else:
        return ','.join(captures.index)

def get_summary_join_col():
    return 'sample' if _is_demux() else 'capture'

rule cr_summarise:
    input:
        individual_summaries=get_summary_inputs,
        captures_config=config["deps"]["captures"]
    output:
        group_summary=temp(out_dir/"summary/metrics/cr_summary.csv")
    params:
        groups=get_summary_groups(),
        join_col=get_summary_join_col()
    container:
        "docker://johnyaku/csvkit:1.1.1"
    shell:
        """
            # Stack the individual summaries with group names
            csvstack --group-name {params.join_col} --groups {params.groups} {input.individual_summaries} \
                > temp_stacked.csv
            
            # Use csvjoin to add pool information from captures config
            csvjoin --no-inference -c {params.join_col} temp_stacked.csv {input.captures_config} \
                > temp_joined.csv
            
            # Capitalize all column headers
            sed '1s/\\b\\w/\\U&/g' temp_joined.csv > {output.group_summary}
            
            # Clean up temp files
            rm temp_stacked.csv temp_joined.csv
        """