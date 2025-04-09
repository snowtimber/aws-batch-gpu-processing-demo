#!/bin/bash
set -e

echo "=== GPU vs CPU Image Processing Benchmark Runner ==="

# Record start time
START_TIME=$(date +%s)
echo "Job submission started at: $(date)"

# OS-independent timestamp conversion function
convert_timestamp() {
    timestamp=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        date -r "$timestamp"
    else
        # Linux and others
        date -d "@$timestamp"
    fi
}

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

# Get the log stream names directly from the job descriptions
GPU_LOG_STREAM=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$GPU_JOB_ID\") | .container.logStreamName")
CPU_LOG_STREAM=$(eval "$DESCRIBE_JOBS_CMD" | jq -r ".jobs[] | select(.jobId == \"$CPU_JOB_ID\") | .container.logStreamName")

echo "GPU log stream: $GPU_LOG_STREAM"
echo "CPU log stream: $CPU_LOG_STREAM"

# Extract benchmark results and instance information
echo "Extracting benchmark results and instance information..."
echo "GPU benchmark:"
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$GPU_LOG_STREAM" --output text | grep -E 'Instance Information|multiplication|Image processing|Gaussian Blur|Start Time|End Time|GPU:|CPU Count:|====' > gpu-benchmark.txt
if [ $? -eq 0 ] && [ -s gpu-benchmark.txt ]; then
    cat gpu-benchmark.txt
else
    echo "Failed to retrieve GPU logs or no matching results found."
    echo "Checking if log stream exists:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "$GPU_LOG_STREAM" --output text
fi

echo "CPU benchmark:"
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$CPU_LOG_STREAM" --output text | grep -E 'Instance Information|multiplication|Image processing|Gaussian Blur|Start Time|End Time|CPU Count:|====' > cpu-benchmark.txt
if [ $? -eq 0 ] && [ -s cpu-benchmark.txt ]; then
    cat cpu-benchmark.txt
else
    echo "Failed to retrieve CPU logs or no matching results found."
    echo "Checking if log stream exists:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "$CPU_LOG_STREAM" --output text
fi

# Create performance comparison
echo "Creating performance comparison..."
echo "=== Performance Comparison ===" > benchmark-summary.txt
echo "Operation,CPU Time (s),GPU Time (s),Speedup Factor" >> benchmark-summary.txt

# Extract matrix multiplication times and calculate speedup
extract_time() {
    grep "$1" "$2" | awk '{print $5}' 2>/dev/null || echo "N/A"
}

calculate_speedup() {
    if [ "$1" != "N/A" ] && [ "$2" != "N/A" ] && [ "$2" != "0.00" ]; then
        echo "scale=2; $1 / $2" | bc 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Matrix multiplication comparisons
for size in 1000 5000 8000; do
    CPU_TIME=$(extract_time "Matrix multiplication ${size}x${size}" cpu-benchmark.txt)
    GPU_TIME=$(extract_time "Matrix multiplication ${size}x${size}" gpu-benchmark.txt)
    SPEEDUP=$(calculate_speedup "$CPU_TIME" "$GPU_TIME")
    echo "Matrix ${size}x${size},$CPU_TIME,$GPU_TIME,$SPEEDUP" >> benchmark-summary.txt
done

# Image processing comparisons
for size in 2048 4096; do
    for batch in 1 2; do
        CPU_TIME=$(grep "Processing images of size ${size}x${size}" -A 3 cpu-benchmark.txt | grep "batch size ${batch}" | awk '{print $5}' 2>/dev/null || echo "N/A")
        GPU_TIME=$(grep "Processing images of size ${size}x${size}" -A 3 gpu-benchmark.txt | grep "batch size ${batch}" | awk '{print $5}' 2>/dev/null || echo "N/A")
        SPEEDUP=$(calculate_speedup "$CPU_TIME" "$GPU_TIME")
        echo "Image ${size}x${size} (batch ${batch}),$CPU_TIME,$GPU_TIME,$SPEEDUP" >> benchmark-summary.txt
    done
done

# Gaussian Blur comparison
CPU_BLUR=$(grep "Gaussian Blur:" cpu-benchmark.txt | awk '{print $3}' 2>/dev/null || echo "N/A")
GPU_BLUR=$(grep "Gaussian Blur:" gpu-benchmark.txt | awk '{print $3}' 2>/dev/null || echo "N/A")
BLUR_SPEEDUP=$(calculate_speedup "$CPU_BLUR" "$GPU_BLUR")
echo "Gaussian Blur,$CPU_BLUR,$GPU_BLUR,$BLUR_SPEEDUP" >> benchmark-summary.txt

# Calculate total benchmark time including provisioning
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_SECONDS / 60))
SECONDS=$((TOTAL_SECONDS % 60))

echo "" >> benchmark-summary.txt
echo "=== Total Benchmark Time (including provisioning) ===" >> benchmark-summary.txt
echo "Start time: $(convert_timestamp $START_TIME)" >> benchmark-summary.txt
echo "End time: $(convert_timestamp $END_TIME)" >> benchmark-summary.txt
echo "Total time: ${MINUTES}m ${SECONDS}s" >> benchmark-summary.txt

# Extract instance information
echo "" >> benchmark-summary.txt
echo "=== Instance Information ===" >> benchmark-summary.txt
echo "GPU Instance:" >> benchmark-summary.txt
grep -A 10 "Instance Information" gpu-benchmark.txt >> benchmark-summary.txt
echo "" >> benchmark-summary.txt
echo "CPU Instance:" >> benchmark-summary.txt
grep -A 10 "Instance Information" cpu-benchmark.txt >> benchmark-summary.txt

# Calculate cost comparison (estimated)
echo "" >> benchmark-summary.txt
echo "=== Cost Efficiency Analysis (Estimated) ===" >> benchmark-summary.txt
GPU_INSTANCE=$(grep "Instance Type:" gpu-benchmark.txt | grep -o 'g[0-9]\.[0-9a-z]*\|p[0-9]\.[0-9a-z]*' || echo "Unknown")
CPU_INSTANCE=$(grep "Instance Type:" cpu-benchmark.txt | grep -o '[rc][0-9]\.[0-9a-z]*\|m[0-9]\.[0-9a-z]*' || echo "Unknown")

# Estimated hourly rates (you can adjust these based on actual pricing)
case "$GPU_INSTANCE" in
    "g5.8xlarge") GPU_RATE=2.88 ;;
    "g5.12xlarge") GPU_RATE=4.32 ;;
    "p3.2xlarge") GPU_RATE=3.06 ;;
    *) GPU_RATE=3.00 ;; # Default estimate
esac

case "$CPU_INSTANCE" in
    "r5.4xlarge") CPU_RATE=1.01 ;;
    "r5.8xlarge") CPU_RATE=2.02 ;;
    "m5.8xlarge") CPU_RATE=1.54 ;;
    "c5.18xlarge") CPU_RATE=3.06 ;;
    *) CPU_RATE=2.00 ;; # Default estimate
esac

echo "GPU Instance: $GPU_INSTANCE (Est. $GPU_RATE/hour)" >> benchmark-summary.txt
echo "CPU Instance: $CPU_INSTANCE (Est. $CPU_RATE/hour)" >> benchmark-summary.txt

# Calculate cost efficiency for matrix multiplication 8000x8000
MATRIX_8K_CPU=$(extract_time "Matrix multiplication 8000x8000" cpu-benchmark.txt)
MATRIX_8K_GPU=$(extract_time "Matrix multiplication 8000x8000" gpu-benchmark.txt)
if [ "$MATRIX_8K_CPU" != "N/A" ] && [ "$MATRIX_8K_GPU" != "N/A" ]; then
    CPU_COST=$(echo "scale=4; $CPU_RATE * $MATRIX_8K_CPU / 3600" | bc)
    GPU_COST=$(echo "scale=4; $GPU_RATE * $MATRIX_8K_GPU / 3600" | bc)
    COST_EFFICIENCY=$(echo "scale=2; $CPU_COST / $GPU_COST" | bc)
    echo "Matrix 8000x8000 Cost Efficiency: $COST_EFFICIENCY (>1 means GPU is more cost-efficient)" >> benchmark-summary.txt
fi

echo "Results saved to gpu-benchmark.txt, cpu-benchmark.txt, and benchmark-summary.txt"
echo "=== Benchmark Complete ==="

# Display summary
echo ""
echo "=== Performance Summary ==="
cat benchmark-summary.txt
