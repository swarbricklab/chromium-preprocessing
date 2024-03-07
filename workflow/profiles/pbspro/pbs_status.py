#!/usr/bin/env python

import sys
import subprocess

def get_pbs_status(job_id):
    try:
        # Execute qstat and capture its output
        result = subprocess.run(['qstat', '-x', job_id], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True)
        
        # Check the job status in the qstat output
        for line in result.stdout.split("\n"):
            if line.strip().startswith("job_state"):
                state = line.split("=")[1].strip()
                if state == "R" or state == "Q":
                    return "running"
                elif state == "C":
                    return "success"
                # Add more conditions for different states if necessary
        return "failed"
    except subprocess.CalledProcessError:
        # If qstat command fails, assume the job is no longer present
        return "failed"

if __name__ == "__main__":
    job_id = sys.argv[1]
    status = get_pbs_status(job_id)
    print(status)

