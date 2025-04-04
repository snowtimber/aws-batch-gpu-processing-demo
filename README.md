<!-- README.md -->
# GPU and CPU Image Processing Benchmark with AWS Batch

This repository contains an AWS SAM template that sets up GPU and CPU benchmarking environments for image processing using AWS Batch. The environment lets you compare the performance of GPU-accelerated workloads against CPU-only processing, with identical workloads for true apples-to-apples comparison.

## Overview

The benchmark runs identical image processing operations on both GPU and CPU instances, allowing you to:

1. Compare execution times between GPU and CPU on the same workloads
2. Measure acceleration factors for different operations
3. Evaluate cost-effectiveness of GPU vs CPU for image workloads
4. Test scaling behavior with different batch and image sizes

## Prerequisites

Before you begin, ensure you have the following:

1. [AWS CLI](https://aws.amazon.com/cli/) installed and configured with appropriate credentials
2. [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) installed
3. Sufficient permissions to create IAM roles, VPC resources, EC2 instances, and AWS Batch resources
4. Sufficient quota to launch GPU instances (p3, g4dn, or g5 instances)

## Step-by-Step Deployment Instructions

### 1. Clone this repository

```bash
git clone https://github.com/yourusername/gpu-batch-benchmark.git
cd gpu-batch-benchmark
```

### 2. Review and update parameters (optional)

Open the `gpu-batch-benchmark.yaml` file and modify the following parameters if needed:

- `MaxvCpus`: Maximum number of vCPUs for the compute environment (default: 64)
- `InstanceTypes`: GPU instance types to use (default: g4dn.xlarge,g5.xlarge,p3.2xlarge)
- `CPUInstanceTypes`: CPU instance types to use (default: c5.2xlarge,c5n.2xlarge,m5.2xlarge)

### 3. Deploy the AWS SAM template

```bash
sam deploy \
  --template-file gpu-batch-benchmark.yaml \
  --stack-name gpu-benchmark \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset
```

The deployment process will create all necessary resources including:
- VPC and networking components
- IAM roles and policies
- AWS Batch compute environments and job queues
- GPU and CPU-optimized job definitions

### 4. Monitor deployment progress

You can monitor the deployment in the AWS CloudFormation console or via the CLI:

```bash
aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].StackStatus"
```

Wait until the deployment status is `CREATE_COMPLETE`.

## Running and Monitoring Benchmarks

Once your deployment is complete, you can use the CloudFormation outputs to run and monitor your benchmarks. Here's a simplified workflow:

### 1. Get all the commands from CloudFormation outputs

First, extract all the useful commands provided by CloudFormation:

```bash
# Extract and save all commands for easy reference
aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs" --output json > benchmark-commands.json

# View the commands in a readable format
cat benchmark-commands.json | jq '.[] | {key: .OutputKey, cmd: .OutputValue}'
```

### 2. Submit benchmark jobs

Use the provided job submission commands:

```bash
# Get and execute the GPU job submission command
SUBMIT_GPU_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitGpuJobCommand'].OutputValue" --output text)
echo "Submitting GPU benchmark job..."
GPU_JOB_RESPONSE=$(eval "$SUBMIT_GPU_CMD")
GPU_JOB_ID=$(echo $GPU_JOB_RESPONSE | jq -r '.jobId')
echo "GPU job submitted with ID: $GPU_JOB_ID"

# Get and execute the CPU job submission command
SUBMIT_CPU_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitCpuJobCommand'].OutputValue" --output text)
echo "Submitting CPU benchmark job..."
CPU_JOB_RESPONSE=$(eval "$SUBMIT_CPU_CMD")
CPU_JOB_ID=$(echo $CPU_JOB_RESPONSE | jq -r '.jobId')
echo "CPU job submitted with ID: $CPU_JOB_ID"
```

### 3. Check job status

Monitor your jobs using the provided commands:

```bash
# Get and use the job status checking command for both jobs
DESCRIBE_JOBS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='DescribeJobsCommand'].OutputValue" --output text)
DESCRIBE_JOBS_CMD=$(echo $DESCRIBE_JOBS_CMD | sed "s/job-id-1/$GPU_JOB_ID/g" | sed "s/job-id-2/$CPU_JOB_ID/g")
echo "Checking job status..."
eval "$DESCRIBE_JOBS_CMD" | jq '.jobs[] | {jobId, jobName, status, statusReason}'
```

### 4. Monitor running jobs

Check which jobs are currently running:

```bash
# Monitor GPU jobs
GPU_JOBS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='ListRunningGpuJobsCommand'].OutputValue" --output text)
echo "Checking running GPU jobs..."
eval "$GPU_JOBS_CMD"

# Monitor CPU jobs
CPU_JOBS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='ListRunningCpuJobsCommand'].OutputValue" --output text)
echo "Checking running CPU jobs..."
eval "$CPU_JOBS_CMD"
```

### 5. View benchmark logs

Once jobs complete (or while they're running), you can view the logs:

```bash
# Get GPU job logs
GPU_LOGS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GetGpuJobLogsCommand'].OutputValue" --output text)
GPU_LOGS_CMD=$(echo $GPU_LOGS_CMD | sed "s/job-id/$GPU_JOB_ID/g")
echo "Fetching GPU job logs..."
eval "$GPU_LOGS_CMD" > gpu-benchmark-full.log

# Get CPU job logs
CPU_LOGS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GetCpuJobLogsCommand'].OutputValue" --output text)
CPU_LOGS_CMD=$(echo $CPU_LOGS_CMD | sed "s/job-id/$CPU_JOB_ID/g")
echo "Fetching CPU job logs..."
eval "$CPU_LOGS_CMD" > cpu-benchmark-full.log
```

### 6. Extract benchmark results

To extract just the benchmark timing results:

```bash
# Extract GPU benchmark results
RESULTS_CMD=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GetBenchmarkResultsCommand'].OutputValue" --output text)
GPU_RESULTS_CMD=$(echo $RESULTS_CMD | sed "s/job-id/$GPU_JOB_ID/g")
echo "Extracting GPU benchmark results..."
eval "$GPU_RESULTS_CMD" > gpu-benchmark-results.txt

# Extract CPU benchmark results
CPU_RESULTS_CMD=$(echo $RESULTS_CMD | sed "s/job-id/$CPU_JOB_ID/g")
echo "Extracting CPU benchmark results..."
eval "$CPU_RESULTS_CMD" > cpu-benchmark-results.txt
```

### 7. Compare results

You can now compare the results between GPU and CPU:

```bash
echo "=== GPU Benchmark Results ==="
cat gpu-benchmark-results.txt

echo "=== CPU Benchmark Results ==="
cat cpu-benchmark-results.txt
```

## One-Click Execution Script

For convenience, here's a complete script that runs all steps and compares results:

```bash
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
```

Save this script as `run-benchmarks.sh`, make it executable (`chmod +x run-benchmarks.sh`), and run it (`./run-benchmarks.sh`).

## Understanding the Benchmark Results

Both the GPU and CPU benchmarks run identical operations on the same data sizes for direct comparison:

1. **Matrix Operations**: Both perform multiplications on matrices sized 1000×1000, 2000×2000, and 5000×5000
2. **Image Processing**: Both process images sized 2048×2048 and 4096×4096 with identical batch sizes (1, 2, 4)
3. **Advanced Image Transformations**: Both apply identical Gaussian blur and edge detection operations

### Analyzing Results Format

The benchmarks output execution times for each operation in this format:

```
Matrix multiplication 1000x1000: X.XX seconds
Matrix multiplication 2000x2000: X.XX seconds
Matrix multiplication 5000x5000: X.XX seconds

Processing images of size 2048x2048
Batch size 1: X.XX seconds
...

Advanced Operations Timing:
Gaussian Blur: X.XX seconds
Edge Detection: X.XX seconds
```

## Creating Performance Comparison Tables

After running the benchmarks, create comparison tables like these using your results:

### Matrix Multiplication Performance

| Matrix Size | GPU Time (s) | CPU Time (s) | Speedup Factor | Cost Efficiency Ratio |
|-------------|--------------|--------------|----------------|------------------------|
| 1000x1000   | ___ s        | ___ s        | ___x           | ___                    |
| 2000x2000   | ___ s        | ___ s        | ___x           | ___                    |
| 5000x5000   | ___ s        | ___ s        | ___x           | ___                    |

### Image Processing Performance (4096x4096)

| Batch Size | GPU Time (s) | CPU Time (s) | Speedup Factor | Cost Efficiency Ratio |
|------------|--------------|--------------|----------------|------------------------|
| 1          | ___ s        | ___ s        | ___x           | ___                    |
| 2          | ___ s        | ___ s        | ___x           | ___                    |
| 4          | ___ s        | ___ s        | ___x           | ___                    |

## Calculating Performance Metrics

1. **Speedup Factor** = CPU time / GPU time
   - Higher is better, indicates how many times faster the GPU is

2. **Cost Efficiency Ratio** = (CPU instance price × CPU time) / (GPU instance price × GPU time)
   - If > 1: GPU is more cost-efficient
   - If < 1: CPU is more cost-efficient

## Example AWS Batch Dashboard Query

You can also create a CloudWatch Dashboard for monitoring your jobs. Here's a sample query:

```
aws cloudwatch get-dashboard --dashboard-name "GPU-CPU-Benchmark" --output json > dashboard.json
```

## Cleaning Up

To avoid ongoing charges, delete all resources:

```bash
aws cloudformation delete-stack --stack-name gpu-benchmark

# Verify deletion is complete
aws cloudformation describe-stacks --stack-name gpu-benchmark
```

## Troubleshooting

### Job Submission Issues

If job submission fails:

```bash
# Check compute environment status
aws batch describe-compute-environments --query "computeEnvironments[?computeEnvironmentName.contains(@,'GPU')].{name:computeEnvironmentName,status:status,state:state,statusReason:statusReason}"
```

### Job Execution Issues

If jobs get stuck in RUNNABLE state:

```bash
# Check if there are instances available in the compute environment
aws batch describe-compute-environments --query "computeEnvironments[?computeEnvironmentName.contains(@,'GPU')].{name:computeEnvironmentName,maxvCpus:computeResources.maxvCpus,desiredvCpus:computeResources.desiredvCpus,minvCpus:computeResources.minvCpus}"

# Check service quotas for the instance types
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

### Viewing Error Logs

If a job fails, check its logs:

```bash
# Replace job-id with your actual job ID
aws batch describe-jobs --jobs job-id --query "jobs[0].{status:status,statusReason:statusReason,container:{reason:container.reason,exitCode:container.exitCode}}"

# Get the log stream and view logs
LOG_STREAM=$(aws batch describe-jobs --jobs job-id --query "jobs[0].container.logStreamName" --output text)
aws logs get-log-events --log-group-name /aws/batch/gpu-benchmark --log-stream-name $LOG_STREAM
```

## Additional Resources

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [NVIDIA CUDA Documentation](https://docs.nvidia.com/cuda/)
- [PyTorch Documentation](https://pytorch.org/docs/)
- [EC2 GPU Instance Types](https://aws.amazon.com/ec2/instance-types/#gpu)
- [AWS GPU Optimization Best Practices](https://docs.aws.amazon.com/dlami/latest/devguide/gpu.html)

## Support

For issues and questions, please file an issue in this GitHub repository.