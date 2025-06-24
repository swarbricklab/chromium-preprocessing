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

rule generate_master_index:
	input:
		predemux_report=rules.predemux_generate_report.output.html,
		cell_types_index=rules.generate_web_indexes.output.cell_types_index,
		summary_index=rules.generate_web_indexes.output.summary_index
	output:
		master_index=report_dir/"cellranger/master_index.html"
	log:
		log_dir/"cellranger_reports/generate_master_indexes.log"
	script:
		"../scripts/build_master_index.py"