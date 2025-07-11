#!/usr/bin/env python3
# Produce a master_index.html that embeds indexes generated in `build_web_indexes.py` plus predemux_report.html

import sys, os, pathlib, html, datetime, base64, shutil

# redirect into Snakemake log
log = open(snakemake.log[0], "w")
sys.stdout = sys.stderr = log

# load template
script_dir    = pathlib.Path(__file__).parent
template_path = script_dir / "base_template.html"
if not template_path.exists():
    sys.exit(f"ERROR: missing base_template.html in {script_dir}")
TEMPLATE = template_path.read_text()

# prepare master entries
entries = []

# Always add the summary report as the first entry with a house icon
# Get the relative path to the summary report
cellranger_summary_report_path = pathlib.Path(snakemake.input.cellranger_summary_report)
summary_href = os.path.relpath(cellranger_summary_report_path, pathlib.Path(snakemake.output.master_index).parent)
home_link_html = (
    f'<a class="home-link" href="{summary_href}" target="viewer">'
    '<i class="bi bi-house"></i> Summary</a>'
)

# Standalone predemux report, only if enabled in input
pred_report = getattr(snakemake.input, "predemux_report", None)
if pred_report:
    pred = pathlib.Path(pred_report)
    href = os.path.relpath(pred, pathlib.Path(snakemake.output.master_index).parent)
    entries.append(("predemux_report", href))
else:
    print("Skipping predemux_report: not enabled or missing in input")

# Add optional cell_types_index if present
cell_types_index = getattr(snakemake.input, "cell_types_index", None)
if cell_types_index:
    p = pathlib.Path(cell_types_index)
    href = os.path.relpath(p, pathlib.Path(snakemake.output.master_index).parent)
    entries.append((p.stem, href))

# summary_index is assumed always present
p = pathlib.Path(snakemake.input.summary_index)
href = os.path.relpath(p, pathlib.Path(snakemake.output.master_index).parent)
entries.append((p.stem, href))

# build <li>
items_html = "\n".join(
    f'      <li data-name="{html.escape(label.lower())}">'\
    f'<a href="{html.escape(href)}">{html.escape(label)}</a></li>'
    for label, href in entries
)

# Copy logo to destination, creating directory if needed
logo_dest = pathlib.Path(snakemake.output.master_index).parent.parent / "resources" / "swarbricklablogo.png"
logo_dest.parent.mkdir(parents=True, exist_ok=True)
if not logo_dest.exists():
    shutil.copy(snakemake.input.logo, logo_dest)
logo_rel_path = os.path.relpath(logo_dest, pathlib.Path(snakemake.output.master_index).parent)
logo_html = (
    '<div class="logo">'
    f'<img src="{logo_rel_path}"'
    '   alt="Swarbrick Lab Logo" '
    '   style="max-width:100%; margin-bottom:1rem;">'
    '</div>'
)

page_title = f"CellRanger Reports"
try:
    out_html   = TEMPLATE.format(
        logo_html=logo_html,
        page_title=html.escape(page_title),
        home_link=home_link_html,  # home icon HTML
        items=items_html,
        timestamp=datetime.datetime.now().isoformat(timespec="seconds"),
        iframe_src=summary_href
    )
except Exception as e:
    print(f"TEMPLATE FORMAT ERROR: {e}")
    import traceback
    traceback.print_exc()
    log.close()
    sys.exit(1)

# write
master_out = pathlib.Path(snakemake.output.master_index)
master_out.parent.mkdir(parents=True, exist_ok=True)
master_out.write_text(out_html)
print(f"Wrote {master_out} with {len(entries)} entries")

log.close()