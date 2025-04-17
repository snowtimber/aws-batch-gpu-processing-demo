#!/bin/bash
# AWS Batch Job Submission Script
#
# This script submits jobs to AWS Batch using a JSON configuration file.
# It supports submitting single jobs or multiple jobs in batch.
#
# Usage:
#   ./submit-job.sh <job-config-file.json> [options]
#
# Options:
#   --monitor            Monitor job status after submission
#   --output <file>      Output file for job IDs
#   --profile <profile>  AWS CLI profile to use
#   --region <region>    AWS region to use
#   --help               Show this help message

set -e

# Default values
MONITOR=false
OUTPUT_FILE=""
PROFILE=""
REGION=""
CONFIG_FILE=""

# Display usage information
show_usage() {
    echo "Usage: $0 <job-config-file.json> [options]"
    echo ""
    echo "This script submits jobs to AWS Batch using a JSON configuration file."
    echo "It supports submitting single jobs or multiple jobs in batch."
    echo ""
    echo "Options:"
    echo "  --monitor            Monitor job status after submission"
    echo "  --output <file>      Output file for job IDs"
    echo "  --profile <profile>  AWS CLI profile to use"
    echo "  --region <region>    AWS region to use"
    echo "  --help               Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 job-config.json --monitor --region us-west-2"
    echo ""
    echo "Job Configuration JSON Format (Single Job):"
    echo "  {"
    echo "    \"jobDefinition\": \"my-job-definition\","
    echo "    \"jobQueue\": \"my-job-queue\","
    echo "    \"jobName\": \"my-job\","
    echo "    \"containerOverrides\": {"
    echo "      \"command\": [\"echo\", \"hello world\"],"
    echo "      \"environment\": ["
    echo "        {\"name\": \"ENV_VAR\", \"value\": \"value\"}"
    echo "      ],"
    echo "      \"resourceRequirements\": ["
    echo "        {\"type\": \"GPU\", \"value\": \"1\"}"
    echo "      ]"
    echo "    }"
    echo "  }"
    echo ""
    echo "Job Configuration JSON Format (Multiple Jobs):"
    echo "  {"
    echo "    \"jobs\": ["
    echo "      {"
    echo "        \"jobDefinition\": \"my-job-definition-1\","
    echo "        \"jobQueue\": \"my-job-queue\","
    echo "        \"jobName\": \"my-job-1\""
    echo "      },"
    echo "      {"
    echo "        \"jobDefinition\": \"my-job-definition-2\","
    echo "        \"jobQueue\": \"my-job-queue\","
    echo "        \"jobName\": \"my-job-2\","
    echo "        \"dependsOn\": ["
    echo "          {\"jobId\": \"\${my-job-1}\", \"type\": \"SEQUENTIAL\"}"
    echo "        ]"
    echo "      }"
    echo "    ]"
    echo "  }"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --help)
            show_usage
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift
            shift
            ;;
        --region)
            REGION="$2"
            shift
            shift
            ;;
        *)
            if [[ -z "$CONFIG_FILE" ]]; then
                CONFIG_FILE="$1"
                shift
            else
                echo "Unknown option: $1"
                show_usage
            fi
            ;;
    esac
done

# Check if config file is provided
if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: Job configuration file is required"
    show_usage
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Job configuration file '$CONFIG_FILE' not found"
    exit 1
fi

# Build AWS CLI base command
AWS_CMD="aws"
if [[ -n "$PROFILE" ]]; then
    AWS_CMD="$AWS_CMD --profile $PROFILE"
fi

if [[ -n "$REGION" ]]; then
    AWS_CMD="$AWS_CMD --region $REGION"
fi

# Function to submit a job
submit_job() {
    local job_json="$1"
    local job_name=$(echo "$job_json" | jq -r '.jobName // "unnamed-job"')
    
    echo "Submitting job: $job_name"
    local job_id=$(echo "$job_json" | $AWS_CMD batch submit-job --cli-input-json - --query 'jobId' --output text)
    
    if [[ -n "$job_id" ]]; then
        echo "Job submitted with ID: $job_id"
        echo "$job_id" >> "$TMP_JOB_IDS"
        # Store job ID with job name for reference
        echo "$job_name:$job_id" >> "$TMP_JOB_NAMES"
    else
        echo "Failed to submit job: $job_name"
    fi
}

# Function to replace job ID references in dependsOn
replace_job_refs() {
    local job_json="$1"
    
    # Check if the job has dependencies
    if echo "$job_json" | jq -e '.dependsOn' > /dev/null 2>&1; then
        # For each dependency
        local deps_count=$(echo "$job_json" | jq '.dependsOn | length')
        for ((i=0; i<$deps_count; i++)); do
            local job_ref=$(echo "$job_json" | jq -r ".dependsOn[$i].jobId")
            
            # If the job ID is a reference (starts with ${)
            if [[ "$job_ref" == \$\{* ]]; then
                # Extract the job name from the reference
                local ref_name=${job_ref:2:-1}
                
                # Look up the job ID for this name
                local actual_id=$(grep "^$ref_name:" "$TMP_JOB_NAMES" | cut -d':' -f2)
                
                if [[ -n "$actual_id" ]]; then
                    # Replace the reference with the actual job ID
                    job_json=$(echo "$job_json" | jq ".dependsOn[$i].jobId = \"$actual_id\"")
                else
                    echo "Warning: Could not find job ID for reference: $job_ref"
                fi
            fi
        done
    fi
    
    echo "$job_json"
}

# Create temporary files for job IDs and job name mappings
TMP_JOB_IDS=$(mktemp)
TMP_JOB_NAMES=$(mktemp)

# Process the configuration file
echo "Processing job configuration from $CONFIG_FILE..."
CONFIG_JSON=$(cat "$CONFIG_FILE")

# Check if the config contains multiple jobs
if echo "$CONFIG_JSON" | jq -e '.jobs' > /dev/null 2>&1; then
    # Multiple jobs
    JOBS_COUNT=$(echo "$CONFIG_JSON" | jq '.jobs | length')
    echo "Found $JOBS_COUNT jobs in configuration"
    
    for ((i=0; i<$JOBS_COUNT; i++)); do
        JOB_JSON=$(echo "$CONFIG_JSON" | jq -c ".jobs[$i]")
        
        # Replace job ID references in dependsOn
        JOB_JSON=$(replace_job_refs "$JOB_JSON")
        
        # Submit the job
        submit_job "$JOB_JSON"
    done
else
    # Single job
    submit_job "$CONFIG_JSON"
fi

# Get the list of submitted job IDs
SUBMITTED_JOB_IDS=$(cat "$TMP_JOB_IDS")
JOB_COUNT=$(echo "$SUBMITTED_JOB_IDS" | wc -l | tr -d ' ')

echo "Total jobs submitted: $JOB_COUNT"

# Write job IDs to output file if requested
if [[ -n "$OUTPUT_FILE" && $JOB_COUNT -gt 0 ]]; then
    cp "$TMP_JOB_IDS" "$OUTPUT_FILE"
    echo "Job IDs written to $OUTPUT_FILE"
fi

# Monitor jobs if requested
if [[ "$MONITOR" = true && $JOB_COUNT -gt 0 ]]; then
    echo "Monitoring $JOB_COUNT jobs..."
    
    # Convert job IDs to an array
    JOB_IDS_ARRAY=()
    while IFS= read -r job_id; do
        JOB_IDS_ARRAY+=("$job_id")
    done < "$TMP_JOB_IDS"
    
    # Monitor jobs until they are all completed
    COMPLETED_JOBS=()
    
    while [[ ${#COMPLETED_JOBS[@]} -lt ${#JOB_IDS_ARRAY[@]} ]]; do
        echo -e "\n========== Job Status Update: $(date) =========="
        
        # Get status for all jobs
        for job_id in "${JOB_IDS_ARRAY[@]}"; do
            # Skip if job is already completed
            if [[ " ${COMPLETED_JOBS[*]} " == *" $job_id "* ]]; then
                continue
            fi
            
            # Get job details
            JOB_DETAILS=$($AWS_CMD batch describe-jobs --jobs "$job_id")
            JOB_NAME=$(echo "$JOB_DETAILS" | jq -r '.jobs[0].jobName')
            JOB_STATUS=$(echo "$JOB_DETAILS" | jq -r '.jobs[0].status')
            
            # Format status with color
            STATUS_DISPLAY="$JOB_STATUS"
            case "$JOB_STATUS" in
                SUCCEEDED)
                    STATUS_DISPLAY="\033[92m$JOB_STATUS\033[0m"  # Green
                    COMPLETED_JOBS+=("$job_id")
                    ;;
                FAILED)
                    STATUS_DISPLAY="\033[91m$JOB_STATUS\033[0m"  # Red
                    COMPLETED_JOBS+=("$job_id")
                    ;;
                RUNNING|STARTING)
                    STATUS_DISPLAY="\033[94m$JOB_STATUS\033[0m"  # Blue
                    ;;
                SUBMITTED)
                    STATUS_DISPLAY="\033[93m$JOB_STATUS\033[0m"  # Yellow
                    ;;
            esac
            
            echo "Job: $JOB_NAME (ID: $job_id) - Status: $STATUS_DISPLAY"
        done
        
        # If not all jobs are completed, wait before checking again
        if [[ ${#COMPLETED_JOBS[@]} -lt ${#JOB_IDS_ARRAY[@]} ]]; then
            echo -e "\nWaiting 30 seconds for next update..."
            sleep 30
        fi
    done
    
    echo -e "\n========== All jobs completed =========="
fi

# Clean up temporary files
rm -f "$TMP_JOB_IDS" "$TMP_JOB_NAMES"
