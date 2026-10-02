# These rules render small HTML reports; run them on the controller rather than
# queuing a compute job for each.
localrules:
    generate_web_indexes,
    generate_summary_report,
    generate_master_index,

# Rule to generate index for all the .html reports
# Use a `capture` column in the config sample sheet
rule generate_web_indexes:
	input:
		captures=config["deps"]["captures"],
		base_template=config["ref"]["report_resources"]+"/base_template.html",
		css_file=config["ref"]["report_resources"]+"/chromium_styles.css"
	output:
		cell_types_index=report_dir/"cellranger/cell_types/cell_types_index.html" if config['params']['extras']['annotate'] else [],
		summary_index=report_dir/"cellranger/web_summaries/summary_index.html"
	log:
		log_dir/"cellranger_reports/generate_web_indexes.log"
	conda:
		"../envs/html_reports.yaml"
	script:
		"../scripts/build_web_indexes.py"

rule generate_summary_report:
	input:
		combined_csv=rules.cr_summarise.output.group_summary,
		summary_template=config["ref"]["report_resources"]+"/summary_template.html",
		css_file=config["ref"]["report_resources"]+"/chromium_styles.css"
	output:
		cellranger_summary_report=report_dir/"cellranger/cellranger_summary_report.html"
	params:
		mode=mode
	log:
		log_dir/"cellranger_reports/generate_summary_report.log"
	conda:
		"../envs/html_reports.yaml"
	script:
		"../scripts/build_cellranger_summary_report.py"

rule generate_master_index:
	input:
		cellranger_summary_report=rules.generate_summary_report.output.cellranger_summary_report,
		summary_index=rules.generate_web_indexes.output.summary_index,
		predemux_report=rules.predemux_generate_report.output.html if config['params']['extras']['predemux'] else [],
		cell_types_index=rules.generate_web_indexes.output.cell_types_index if config['params']['extras']['annotate'] else [],
		base_template=config["ref"]["report_resources"]+"/base_template.html",
		css_file=config["ref"]["report_resources"]+"/chromium_styles.css",
		logo=config["ref"]["report_resources"]+"/swarbricklablogo.png"
	output:
		master_index=report_dir/"cellranger/master_index.html"
	log:
		log_dir/"cellranger_reports/generate_master_indexes.log"
	conda:
		"../envs/html_reports.yaml"
	script:
		"../scripts/build_master_index.py"