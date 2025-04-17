#!/bin/bash
# AWS Batch Job Definition Creation Script
#
# This script creates and registers an AWS Batch job definition from a JSON file.
# It simplifies the process of creating job definitions for AWS Batch.
#
# Usage:
#   ./create-job-definition.sh <job-definition-file.json> [options]
#
# Options:
#   --profile <profile>  AWS CLI profile to use
#   --region <region>    AWS region to use
#   --output <format>    Output format (json, text, table)
#   --help               Show this help message

set -e

# Default values
PROFILE=""
REGION=""
OUTPUT_FORMAT="json"
JOB_DEF_FILE=""

# Display usage information
show_usage() {
    echo "Usage: $0 <job-definition-file.json> [options]"
    echo ""
    echo "This script creates and registers an AWS Batch job definition from a JSON file."
    echo ""
    echo "Options:"
    echo "  --profile <profile>  AWS CLI profile to use"
    echo "  --region <region>    AWS region to use"
    echo "  --output <format>    Output format (json, text, table)"
    echo "  --help               Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 job-definition.json --region us-west-2"
    echo ""
    echo "Job Definition JSON Format:"
    echo "  {"
    echo "    \"jobDefinitionName\": \"my-job-definition\","
    echo "    \"type\": \"container\","
    echo "    \"containerProperties\": {"
    echo "      \"image\": \"my-docker-image:latest\","
    echo "      \"vcpus\": 2,"
    echo "      \"memory\": 2048,"
    echo "      \"command\": [\"echo\", \"hello world\"],"
    echo "      \"jobRoleArn\": \"arn:aws:iam::123456789012:role/my-job-role\","
    echo "      \"environment\": ["
    echo "        {\"name\": \"ENV_VAR\", \"value\": \"value\"}"
    echo "      ],"
    echo "      \"resourceRequirements\": ["
    echo "        {\"type\": \"GPU\", \"value\": \"1\"}"
    echo "      ]"
    echo "    },"
    echo "    \"timeout\": {"
    echo "      \"attemptDurationSeconds\": 3600"
    echo "    },"
    echo "    \"retryStrategy\": {"
    echo "      \"attempts\": 1"
    echo "    }"
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
        --output)
            OUTPUT_FORMAT="$2"
            shift
            shift
            ;;
        *)
            if [[ -z "$JOB_DEF_FILE" ]]; then
                JOB_DEF_FILE="$1"
                shift
            else
                echo "Unknown option: $1"
                show_usage
            fi
            ;;
    esac
done

# Check if job definition file is provided
if [[ -z "$JOB_DEF_FILE" ]]; then
    echo "Error: Job definition file is required"
    show_usage
fi

# Check if job definition file exists
if [[ ! -f "$JOB_DEF_FILE" ]]; then
    echo "Error: Job definition file '$JOB_DEF_FILE' not found"
    exit 1
fi

# Build AWS CLI command
CMD="aws batch register-job-definition --cli-input-json file://$JOB_DEF_FILE --output $OUTPUT_FORMAT"

if [[ -n "$PROFILE" ]]; then
    CMD="$CMD --profile $PROFILE"
fi

if [[ -n "$REGION" ]]; then
    CMD="$CMD --region $REGION"
fi

# Execute the command
echo "Registering job definition from $JOB_DEF_FILE..."
eval $CMD

echo "Job definition registered successfully."
