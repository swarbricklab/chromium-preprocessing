# Rule to generate index for all the .html reports
# Use a `capture` column in the config sample sheet
rule generate_web_indexes:
	input:
		captures=config["deps"]["captures"]
	output:
		cell_types_index=report_dir/"web/captures/cell_types_index.html",
		summary_index=report_dir/"web/captures/summary_index.html"
	params:
		annotate=config['params']['extras']['annotate']
	log:
		log_dir/"cellranger_reports/generate_web_indexes.log"
	conda:
		"../envs/html_reports.yaml"
	script:
		"../scripts/build_web_indexes.py"

if config.get("params", {}).get("extras", {}).get("summary_report", True):
	rule generate_summary_report:
		input:
			combined_csv=rules.cr_summarise.output.group_summary,
			cell_types_index=rules.generate_web_indexes.output.cell_types_index,
			summary_index=rules.generate_web_indexes.output.summary_index
		output:
			summary_report=report_dir/"cellranger/summary_report.html"
		log:
			log_dir/"cellranger_reports/generate_summary_report.log"
		conda:
			"../envs/html_reports.yaml"
		script:
			"../scripts/build_summary_report.py"
else:
	rule generate_summary_report:
		output:
			summary_report=report_dir/"cellranger/summary_report.html"
		log:
			log_dir/"cellranger_reports/generate_summary_report.log"
		shell:
			"echo 'Summary report generation is currently disabled.' | tee {log} > {output.summary_report}"

rule generate_master_index:
	input:
		logo=config["ref"]["logo"],
		summary_report=rules.generate_summary_report.output.summary_report,
		predemux_report=rules.predemux_generate_report.output.html if config['params']['extras']['predemux'] else [],
		cell_types_index=rules.generate_web_indexes.output.cell_types_index if config['params']['extras']['annotate'] else [],
		summary_index=rules.generate_web_indexes.output.summary_index
	output:
		master_index=report_dir/"cellranger/master_index.html"
	params:
		predemux=config['params']['extras']['predemux']
	log:
		log_dir/"cellranger_reports/generate_master_indexes.log"
	conda:
		"../envs/html_reports.yaml"
	script:
		"../scripts/build_master_index.py"