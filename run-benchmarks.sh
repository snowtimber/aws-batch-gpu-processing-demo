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
GPU_RESULTS_CMD=$(echo $GET_RESULTS_BASE | sed "s/job-id/$GPU_JOB_ID/g")
CPU_RESULTS_CMD=$(echo $GET_RESULTS_BASE | sed "s/job-id/$CPU_JOB_ID/g")

echo "GPU results:"
eval "$GPU_RESULTS_CMD" > gpu-results.txt
cat gpu-results.txt

echo "CPU results:"
eval "$CPU_RESULTS_CMD" > cpu-results.txt
cat cpu-results.txt

echo "Results saved to gpu-results.txt and cpu-results.txt"
echo "=== Benchmark Complete ==="