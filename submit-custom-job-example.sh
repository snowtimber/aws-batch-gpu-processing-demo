#!/bin/bash
# Example script demonstrating how to submit a custom job to AWS Batch
# This example shows how to submit a job with custom parameters

set -e

echo "=== AWS Batch Custom Job Submission Example ==="

# Get the job queue and job definition ARNs from CloudFormation outputs
echo "Getting job queue and job definition ARNs from CloudFormation..."
GPU_JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuJobQueue'].OutputValue" --output text)
CPU_JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='CpuJobQueue'].OutputValue" --output text)
GPU_JOB_DEF=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuJobDefinition'].OutputValue" --output text)
CPU_JOB_DEF=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='CpuJobDefinition'].OutputValue" --output text)

echo "GPU Job Queue: $GPU_JOB_QUEUE"
echo "CPU Job Queue: $CPU_JOB_QUEUE"
echo "GPU Job Definition: $GPU_JOB_DEF"
echo "CPU Job Definition: $CPU_JOB_DEF"

# Example 1: Submit a single GPU job with custom parameters
echo -e "\n=== Example 1: Submit a single GPU job with custom parameters ==="
./submit-jobs.sh \
  --job-definition "$GPU_JOB_DEF" \
  --job-queue "$GPU_JOB_QUEUE" \
  --job-name "custom-gpu-job-$(date +%Y%m%d%H%M%S)" \
  --env "MODEL_TYPE=resnet50,BATCH_SIZE=32" \
  --monitor

# Example 2: Submit multiple CPU jobs
echo -e "\n=== Example 2: Submit multiple CPU jobs ==="
./submit-jobs.sh \
  --job-definition "$CPU_JOB_DEF" \
  --job-queue "$CPU_JOB_QUEUE" \
  --job-name "custom-cpu-job" \
  --count 3 \
  --monitor

# Example 3: Submit jobs using a configuration file
echo -e "\n=== Example 3: Submit jobs using a configuration file ==="

# Create a temporary configuration file
CONFIG_FILE="temp-batch-jobs.json"

cat > "$CONFIG_FILE" << EOF
{
  "jobs": [
    {
      "jobDefinition": "$GPU_JOB_DEF",
      "jobQueue": "$GPU_JOB_QUEUE",
      "jobName": "config-gpu-job-1",
      "containerOverrides": {
        "environment": [
          {"name": "MODEL_TYPE", "value": "resnet50"},
          {"name": "BATCH_SIZE", "value": "32"}
        ],
        "resourceRequirements": [
          {"type": "GPU", "value": "1"}
        ]
      }
    },
    {
      "jobDefinition": "$CPU_JOB_DEF",
      "jobQueue": "$CPU_JOB_QUEUE",
      "jobName": "config-cpu-job-1",
      "containerOverrides": {
        "environment": [
          {"name": "MODEL_TYPE", "value": "mobilenet"},
          {"name": "BATCH_SIZE", "value": "64"}
        ]
      }
    }
  ]
}
EOF

./submit-jobs.sh --config "$CONFIG_FILE" --monitor

# Clean up temporary file
rm -f "$CONFIG_FILE"

echo -e "\n=== Job submission examples completed ==="
