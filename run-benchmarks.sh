#!/bin/bash
set -e

echo "=== GPU vs CPU Image Processing Benchmark Runner ==="

# Extract commands from CloudFormation
echo "Getting commands from CloudFormation..."
SUBMIT_GPU_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitGpuJobCommand'].OutputValue" --output text)
SUBMIT_CPU_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitCpuJobCommand'].OutputValue" --output text)
DESCRIBE_JOBS_BASE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='DescribeJobsCommand'].OutputValue" --output text)
GET_RESULTS_BASE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GetBenchmarkResultsCommand'].OutputValue" --output text)

# Submit jobs
echo "Submitting GPU benchmark job..."
GPU_JOB_RESPONSE=$(eval "$SUBMIT_GPU_CMD")
GPU_JOB_ID=$(echo $GPU_JOB_RESPONSE | jq -r '.jobId')
echo "GPU job submitted with ID: $GPU_JOB_ID"

echo "Submitting CPU benchmark job..."
CPU_JOB_RESPONSE=$(eval "$SUBMIT_CPU_CMD")
CPU_JOB_ID=$(echo $CPU_JOB_RESPONSE | jq -r '.jobId')
echo "CPU job submitted with ID: $CPU_JOB_ID"

# Monitor job progress
echo "Monitoring job status (press Ctrl+C to stop monitoring)..."
DESCRIBE_JOBS_CMD=$(echo $DESCRIBE_JOBS_BASE | sed "s/job-id-1/$GPU_JOB_ID/g" | sed "s/job-id-2/$CPU_JOB_ID/g")

while true; do
  clear
  echo "=== Current Job Status ==="
  eval "$DESCRIBE_JOBS_CMD" | jq '.jobs[] | {jobName, status, statusReason, startedAt, stoppedAt}'
  
  # Check if both jobs are done
  GPU_STATUS=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$GPU_JOB_ID\") | .status")
  CPU_STATUS=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$CPU_JOB_ID\") | .status")
  
  if [[ "$GPU_STATUS" == "SUCCEEDED" && "$CPU_STATUS" == "SUCCEEDED" ]]; then
    echo "Both jobs completed successfully!"
    break
  fi
  
  if [[ "$GPU_STATUS" == "FAILED" ]]; then
    echo "GPU job failed. Check logs for details."
  fi
  
  if [[ "$CPU_STATUS" == "FAILED" ]]; then
    echo "CPU job failed. Check logs for details."
  fi
  
  sleep 30
done

# Extract results
echo "Extracting benchmark results..."

# Get job definitions to construct the log stream names
GPU_JOB_DEF=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$GPU_JOB_ID\") | .jobDefinition" | cut -d "/" -f 2 | cut -d ":" -f 1)
CPU_JOB_DEF=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$CPU_JOB_ID\") | .jobDefinition" | cut -d "/" -f 2 | cut -d ":" -f 1)

echo "GPU job definition: $GPU_JOB_DEF"
echo "CPU job definition: $CPU_JOB_DEF"

# Construct the correct log stream names
GPU_LOG_STREAM="${GPU_JOB_DEF}/default/${GPU_JOB_ID}"
CPU_LOG_STREAM="${CPU_JOB_DEF}/default/${CPU_JOB_ID}"

echo "GPU log stream: $GPU_LOG_STREAM"
echo "CPU log stream: $CPU_LOG_STREAM"

# Extract GPU results
echo "GPU results:"
echo "Fetching from log group: /aws/batch/job, stream: $GPU_LOG_STREAM"
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$GPU_LOG_STREAM" --output text | grep -E 'multiplication|Batch size|Operation' > gpu-results.txt
if [ $? -eq 0 ] && [ -s gpu-results.txt ]; then
    cat gpu-results.txt
else
    echo "Failed to retrieve GPU logs or no matching results found."
    echo "Listing available log streams for this job:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "${GPU_JOB_DEF}/default/${GPU_JOB_ID}" --output text
fi

# Extract CPU results
echo "CPU results:"
echo "Fetching from log group: /aws/batch/job, stream: $CPU_LOG_STREAM"
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$CPU_LOG_STREAM" --output text | grep -E 'multiplication|Batch size|Operation' > cpu-results.txt
if [ $? -eq 0 ] && [ -s cpu-results.txt ]; then
    cat cpu-results.txt
else
    echo "Failed to retrieve CPU logs or no matching results found."
    echo "Listing available log streams for this job:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "${CPU_JOB_DEF}/default/${CPU_JOB_ID}" --output text
fi

echo "Results saved to gpu-results.txt and cpu-results.txt"
echo "=== Benchmark Complete ==="
