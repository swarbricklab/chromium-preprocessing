
# Look up field in sample_sheet
def capturesheet(field):
    def handle_wildcards(wildcards):
        result=captures.loc[wildcards.capture, field]
        return result.split(";")
    return handle_wildcards
