
# Look up field in sample_sheet
def capturesheet(field):
    def handle_wildcards(wildcards):
        return captures.loc[wildcards.capture, field]
    return handle_wildcards
