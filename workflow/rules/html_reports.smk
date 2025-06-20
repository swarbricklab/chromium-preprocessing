# Rule to generate index for all the .html reports
# Use a `capture` column in the config sample sheet
rule generate_web_indexes:
	input:
		captures=config["deps"]["captures"]
	output:
		cell_types_index="reports/cellranger/web/captures/cell_types_index.html"
		summary_index="reports/cellranger/web/captures/summary_index.html"
	log:
        "logs/chromium-preprocessing/cellranger_reports/generate_web_indexes.log"
	script:
        "../scripts/build_web_indexes.py"

rule generate_master_index:
	input:
		predemux_report="reports/cellranger/predemux/predemux_report.html"
		cell_types_index="reports/cellranger/web/captures/cell_types_index.html"
		summary_index="reports/cellranger/web/captures/summary_index.html"
	output:
		master_index="reports/cellranger/master_index.html
	log:
		"logs/chromium-preprocessing/cellranger_reports/generate_master_indexes.log"
	script:
		"../scripts/build_master_index.py"