# Rule to generate index for all the .html reports
# Use a `capture` column in the config sample sheet
rule generate_web_indexes:
	input:
		captures=config["deps"]["captures"]
	output:
		cell_types_index=report_dir/"web/captures/cell_types_index.html",
		summary_index=report_dir/"web/captures/summary_index.html"
	log:
		log_dir/"cellranger_reports/generate_web_indexes.log"
	script:
		"../scripts/build_web_indexes.py"

rule generate_summary_report:
	input:
		cell_types_index=rules.generate_web_indexes.output.cell_types_index,
		summary_index=rules.generate_web_indexes.output.summary_index
	output:
		summary_report=report_dir/"summary_report.html"
	log:
		log_dir/"cellranger_reports/generate_summary_report.log"
	script:
		"../scripts/build_summary_report.py"

rule generate_master_index:
	input:
		logo=config["ref"]["logo"],
		predemux_report=rules.predemux_generate_report.output.html if config['params']['extras']['predemux'] else "",
		cell_types_index=rules.generate_web_indexes.output.cell_types_index if config['params']['extras']['annotate'] else "",
		summary_index=rules.generate_web_indexes.output.summary_index
	output:
		logo=report_dir/"resources/swarbricklablogo.png",
		master_index=report_dir/"master_index.html"
	log:
		log_dir/"cellranger_reports/generate_master_indexes.log"
	script:
		"../scripts/build_master_index.py"