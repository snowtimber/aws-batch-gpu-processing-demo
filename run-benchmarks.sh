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
# Get logs and format as timestamp + message
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$GPU_LOG_STREAM" --output text | grep -E 'GPU BENCHMARK|CPU BENCHMARK|Instance Information|Instance Type:|multiplication|Image processing|Gaussian Blur|Start Time|End Time|Total Job Time|GPU:|CPU Count:|====' | \
  awk '{
    # Extract the timestamp (last field)
    timestamp = $NF
    # Extract the message (everything except EVENTS, first timestamp, and last timestamp)
    message = ""
    for (i=3; i<NF; i++) {
      message = message $i " "
    }
    # Print timestamp and message
    print timestamp "\t" message
  }' > gpu-benchmark.txt
if [ $? -eq 0 ] && [ -s gpu-benchmark.txt ]; then
    cat gpu-benchmark.txt
else
    echo "Failed to retrieve GPU logs or no matching results found."
    echo "Checking if log stream exists:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "$GPU_LOG_STREAM" --output text
fi

echo "CPU benchmark:"
# Get logs and format as timestamp + message
aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name "$CPU_LOG_STREAM" --output text | grep -E 'GPU BENCHMARK|CPU BENCHMARK|Instance Information|Instance Type:|multiplication|Image processing|Gaussian Blur|Start Time|End Time|Total Job Time|GPU:|CPU Count:|====' | \
  awk '{
    # Extract the timestamp (last field)
    timestamp = $NF
    # Extract the message (everything except EVENTS, first timestamp, and last timestamp)
    message = ""
    for (i=3; i<NF; i++) {
      message = message $i " "
    }
    # Print timestamp and message
    print timestamp "\t" message
  }' > cpu-benchmark.txt
if [ $? -eq 0 ] && [ -s cpu-benchmark.txt ]; then
    cat cpu-benchmark.txt
else
    echo "Failed to retrieve CPU logs or no matching results found."
    echo "Checking if log stream exists:"
    aws logs describe-log-streams --log-group-name "/aws/batch/job" --log-stream-name-prefix "$CPU_LOG_STREAM" --output text
fi

# Create performance comparison with a nice ASCII table
echo "Creating performance comparison..."
echo "=== Performance Comparison ===" > benchmark-summary.txt
echo "+-------------------------+---------------+---------------+----------------+" >> benchmark-summary.txt
echo "| Operation               | CPU Time (s)  | GPU Time (s)  | Speedup Factor |" >> benchmark-summary.txt
echo "+-------------------------+---------------+---------------+----------------+" >> benchmark-summary.txt

# Extract times from log files with timestamp prefix
extract_time() {
    grep "$1" "$2" | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A"
}

calculate_speedup() {
    if [ "$1" != "N/A" ] && [ "$2" != "N/A" ] && [ "$2" != "0.00" ] && [ "$2" != "0" ]; then
        # Check if GPU time is very close to zero (less than 0.001)
        if (( $(echo "$2 < 0.001" | bc -l) )); then
            echo "Infinite"  # Avoid division by very small numbers
        else
            echo "scale=2; $1 / $2" | bc 2>/dev/null || echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Format table row with proper padding
format_row() {
    operation=$1
    cpu_time=$2
    gpu_time=$3
    speedup=$4
    
    # Ensure values have consistent formatting
    if [ "$cpu_time" != "N/A" ] && [[ "$cpu_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        cpu_time=$(printf "%.2f" $cpu_time)
    fi
    
    if [ "$gpu_time" != "N/A" ] && [[ "$gpu_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        gpu_time=$(printf "%.2f" $gpu_time)
    fi
    
    printf "| %-23s | %-13s | %-13s | %-14s |\n" "$operation" "$cpu_time" "$gpu_time" "$speedup" >> benchmark-summary.txt
}

# Matrix multiplication comparisons
for size in 1000 5000 8000 10000; do
    CPU_TIME=$(grep "Matrix multiplication ${size}x${size}:" cpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
    GPU_TIME=$(grep "Matrix multiplication ${size}x${size}:" gpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
    SPEEDUP=$(calculate_speedup "$CPU_TIME" "$GPU_TIME")
    format_row "Matrix ${size}x${size}" "$CPU_TIME" "$GPU_TIME" "$SPEEDUP"
done

# Image processing comparisons - use a more precise approach based on the exact log format
# First find the lines with "batch size 1" and "batch size 2"
CPU_BATCH1_2048=$(grep "batch size 1" cpu-benchmark.txt | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
CPU_BATCH2_2048=$(grep "batch size 2" cpu-benchmark.txt | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
CPU_BATCH1_4096=$(grep "batch size 1" cpu-benchmark.txt | tail -2 | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
CPU_BATCH2_4096=$(grep "batch size 2" cpu-benchmark.txt | tail -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")

# Same for GPU
GPU_BATCH1_2048=$(grep "batch size 1" gpu-benchmark.txt | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
GPU_BATCH2_2048=$(grep "batch size 2" gpu-benchmark.txt | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
GPU_BATCH1_4096=$(grep "batch size 1" gpu-benchmark.txt | tail -2 | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
GPU_BATCH2_4096=$(grep "batch size 2" gpu-benchmark.txt | tail -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")

# Calculate speedups
SPEEDUP_2048_1=$(calculate_speedup "$CPU_BATCH1_2048" "$GPU_BATCH1_2048")
SPEEDUP_2048_2=$(calculate_speedup "$CPU_BATCH2_2048" "$GPU_BATCH2_2048")
SPEEDUP_4096_1=$(calculate_speedup "$CPU_BATCH1_4096" "$GPU_BATCH1_4096")
SPEEDUP_4096_2=$(calculate_speedup "$CPU_BATCH2_4096" "$GPU_BATCH2_4096")

# Format rows
format_row "Image 2048x2048 (batch 1)" "$CPU_BATCH1_2048" "$GPU_BATCH1_2048" "$SPEEDUP_2048_1"
format_row "Image 2048x2048 (batch 2)" "$CPU_BATCH2_2048" "$GPU_BATCH2_2048" "$SPEEDUP_2048_2"
format_row "Image 4096x4096 (batch 1)" "$CPU_BATCH1_4096" "$GPU_BATCH1_4096" "$SPEEDUP_4096_1"
format_row "Image 4096x4096 (batch 2)" "$CPU_BATCH2_4096" "$GPU_BATCH2_4096" "$SPEEDUP_4096_2"

# Gaussian Blur comparison - use a more precise approach
CPU_BLUR=$(grep "Gaussian Blur:" cpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
GPU_BLUR=$(grep "Gaussian Blur:" gpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")

BLUR_SPEEDUP=$(calculate_speedup "$CPU_BLUR" "$GPU_BLUR")
format_row "Gaussian Blur" "$CPU_BLUR" "$GPU_BLUR" "$BLUR_SPEEDUP"

# Extract the total job times
GPU_JOB_TIME=$(grep "Total Job Time:" gpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")
CPU_JOB_TIME=$(grep "Total Job Time:" cpu-benchmark.txt | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "N/A")

# Calculate speedup for total job time
if [[ "$GPU_JOB_TIME" != "N/A" && "$CPU_JOB_TIME" != "N/A" ]]; then
    JOB_SPEEDUP=$(echo "scale=2; $CPU_JOB_TIME / $GPU_JOB_TIME" | bc 2>/dev/null || echo "N/A")
else
    JOB_SPEEDUP="N/A"
fi

# Add a separator line in the table
echo "+-------------------------+---------------+---------------+----------------+" >> benchmark-summary.txt

# Add total job times to the main table
format_row "Total Job Time" "$CPU_JOB_TIME" "$GPU_JOB_TIME" "$JOB_SPEEDUP"

# Add table footer
echo "+-------------------------+---------------+---------------+----------------+" >> benchmark-summary.txt

echo "Results saved to gpu-benchmark.txt, cpu-benchmark.txt, and benchmark-summary.txt"
echo "=== Benchmark Complete ==="

# Display summary
echo ""
cat benchmark-summary.txt
