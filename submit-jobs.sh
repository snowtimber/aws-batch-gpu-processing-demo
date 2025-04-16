#!/bin/bash
# Simple wrapper script for submit-batch-jobs.py
# Makes it easier to submit AWS Batch jobs

set -e

# Default values
CONFIG_FILE=""
JOB_DEFINITION=""
JOB_QUEUE=""
JOB_NAME=""
COMMAND=""
ENV_VARS=""
MEMORY=""
VCPUS=""
GPU=""
TIMEOUT=""
COUNT=1
DEPENDS_ON=""
ARRAY_SIZE=""
OUTPUT_FILE=""
MONITOR=false
REGION=""
PROFILE=""

# Display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -c, --config FILE          Path to JSON configuration file"
    echo "  -d, --job-definition DEF   Job definition name or ARN"
    echo "  -q, --job-queue QUEUE      Job queue name or ARN"
    echo "  -n, --job-name NAME        Name for the job"
    echo "  --command CMD              Command override for the job"
    echo "  --env KEY=VAL,KEY2=VAL2    Environment variables"
    echo "  --memory MB                Memory override in MB"
    echo "  --vcpus NUM                vCPUs override"
    echo "  --gpu NUM                  Number of GPUs to use"
    echo "  --timeout SEC              Timeout in seconds"
    echo "  --count NUM                Number of identical jobs to submit (default: 1)"
    echo "  --depends-on IDS           Job IDs this job depends on, comma separated"
    echo "  --array-size SIZE          Size of the job array"
    echo "  --output FILE              Output file for job IDs"
    echo "  --monitor                  Monitor job status after submission"
    echo "  --region REGION            AWS region"
    echo "  --profile PROFILE          AWS profile name"
    echo ""
    echo "Examples:"
    echo "  $0 --config batch-jobs.json"
    echo "  $0 --job-definition gpu-image-processing-benchmark --job-queue GpuJobQueue --job-name my-job"
    echo "  $0 --job-definition cpu-image-processing-benchmark --job-queue CPUJobQueue --count 5 --monitor"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_usage
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift
            shift
            ;;
        -d|--job-definition)
            JOB_DEFINITION="$2"
            shift
            shift
            ;;
        -q|--job-queue)
            JOB_QUEUE="$2"
            shift
            shift
            ;;
        -n|--job-name)
            JOB_NAME="$2"
            shift
            shift
            ;;
        --command)
            COMMAND="$2"
            shift
            shift
            ;;
        --env)
            ENV_VARS="$2"
            shift
            shift
            ;;
        --memory)
            MEMORY="$2"
            shift
            shift
            ;;
        --vcpus)
            VCPUS="$2"
            shift
            shift
            ;;
        --gpu)
            GPU="$2"
            shift
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift
            shift
            ;;
        --count)
            COUNT="$2"
            shift
            shift
            ;;
        --depends-on)
            DEPENDS_ON="$2"
            shift
            shift
            ;;
        --array-size)
            ARRAY_SIZE="$2"
            shift
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --region)
            REGION="$2"
            shift
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Build command
CMD="python3 submit-batch-jobs.py"

# Add options
if [ -n "$CONFIG_FILE" ]; then
    CMD="$CMD --config $CONFIG_FILE"
fi

if [ -n "$JOB_DEFINITION" ]; then
    CMD="$CMD --job-definition $JOB_DEFINITION"
fi

if [ -n "$JOB_QUEUE" ]; then
    CMD="$CMD --job-queue $JOB_QUEUE"
fi

if [ -n "$JOB_NAME" ]; then
    CMD="$CMD --job-name $JOB_NAME"
fi

if [ -n "$COMMAND" ]; then
    CMD="$CMD --command \"$COMMAND\""
fi

if [ -n "$ENV_VARS" ]; then
    CMD="$CMD --env \"$ENV_VARS\""
fi

if [ -n "$MEMORY" ]; then
    CMD="$CMD --memory $MEMORY"
fi

if [ -n "$VCPUS" ]; then
    CMD="$CMD --vcpus $VCPUS"
fi

if [ -n "$GPU" ]; then
    CMD="$CMD --gpu $GPU"
fi

if [ -n "$TIMEOUT" ]; then
    CMD="$CMD --timeout $TIMEOUT"
fi

if [ "$COUNT" -ne 1 ]; then
    CMD="$CMD --count $COUNT"
fi

if [ -n "$DEPENDS_ON" ]; then
    CMD="$CMD --depends-on \"$DEPENDS_ON\""
fi

if [ -n "$ARRAY_SIZE" ]; then
    CMD="$CMD --array-size $ARRAY_SIZE"
fi

if [ -n "$OUTPUT_FILE" ]; then
    CMD="$CMD --output $OUTPUT_FILE"
fi

if [ "$MONITOR" = true ]; then
    CMD="$CMD --monitor"
fi

if [ -n "$REGION" ]; then
    CMD="$CMD --region $REGION"
fi

if [ -n "$PROFILE" ]; then
    CMD="$CMD --profile $PROFILE"
fi

# Check if we have enough parameters
if [ -z "$CONFIG_FILE" ] && ([ -z "$JOB_DEFINITION" ] || [ -z "$JOB_QUEUE" ]); then
    echo "Error: Either --config or both --job-definition and --job-queue must be provided"
    show_usage
fi

# Execute the command
echo "Executing: $CMD"
eval $CMD
