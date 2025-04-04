<!-- README.md -->
# GPU and CPU Image Processing Benchmark with AWS Batch

This repository contains an AWS SAM template that sets up GPU and CPU benchmarking environments for image processing using AWS Batch. The environment lets you compare the performance of GPU-accelerated workloads against CPU-only processing.

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

### 5. Get the job submission commands directly from CloudFormation outputs

Once the deployment is complete, you can retrieve the exact commands to run without any modification:

```bash
# Get and execute the GPU job submission command
$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitGpuJobCommand'].OutputValue" --output text)

# Get and execute the CPU job submission command
$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='SubmitCpuJobCommand'].OutputValue" --output text)
```

These commands will automatically:
1. Pull the correct job queue ARNs from your deployment
2. Pull the correct job definition ARNs
3. Generate unique job names with timestamps
4. Submit the jobs to AWS Batch

### 6. Track your job IDs

When you submit the jobs, AWS Batch will return a response like this:

```json
{
    "jobArn": "arn:aws:batch:region:account:job/job-id",
    "jobName": "gpu-benchmark-20230808123456",
    "jobId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
}
```

Save these job IDs for the next steps.

### 7. Monitor job status

You can track the status of your jobs using the job IDs:

```bash
# Check status of specific jobs
aws batch describe-jobs --jobs job-id-1 job-id-2

# List all GPU jobs with a specific status
JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuJobQueue'].OutputValue" --output text)
aws batch list-jobs --job-queue $JOB_QUEUE --status RUNNING

# List all CPU jobs with a specific status
JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='CpuJobQueue'].OutputValue" --output text)
aws batch list-jobs --job-queue $JOB_QUEUE --status RUNNING
```

Job status progression: SUBMITTED → PENDING → RUNNABLE → STARTING → RUNNING → SUCCEEDED (or FAILED)

### 8. View job logs to see benchmark results

To view the logs and benchmark results:

```bash
# Get the log stream for a job
LOG_STREAM=$(aws batch describe-jobs --jobs your-job-id --query "jobs[0].container.logStreamName" --output text)

# View the full log
aws logs get-log-events --log-group-name /aws/batch/gpu-benchmark --log-stream-name $LOG_STREAM --output text

# Get just the benchmark results (helpful for large logs)
aws logs get-log-events --log-group-name /aws/batch/gpu-benchmark --log-stream-name $LOG_STREAM --output text | grep -E "multiplication|Batch size|Operation"
```

You can also view the logs in the AWS CloudWatch console for a more user-friendly experience.

## Understanding the Benchmark Results

Both the GPU and CPU benchmarks run the same operations on the same image sizes for direct comparison, including:

1. **Matrix Operations**: Both perform operations on matrices sized 1000×1000, 2000×2000, and 5000×5000
2. **Image Processing**: Both process images sized 2048×2048 and 4096×4096 with various batch sizes
3. **Advanced Image Transformations**: Both apply identical Gaussian blur and edge detection operations

> **Note**: While the benchmarks use the same algorithms and image sizes, be aware that the CPU benchmark may time out on very large workloads. If this happens, examine the partial results and estimate completion time based on the operations that did complete.

### Analyzing Results Format

The benchmarks output execution times for each operation. Here's a sample output structure:

```
=== [GPU/CPU] Benchmark for Image Processing ===
[Device information]

=== 1. Running Matrix Operations Benchmark ===
Matrix multiplication 1000x1000: X.XX seconds
Matrix multiplication 2000x2000: X.XX seconds
Matrix multiplication 5000x5000: X.XX seconds

=== 2. Running Image Processing Benchmark ===

Processing images of size 2048x2048
Batch size 1: X.XX seconds
Batch size 2: X.XX seconds
Batch size 4: X.XX seconds

Processing images of size 4096x4096
Batch size 1: X.XX seconds
Batch size 2: X.XX seconds
Batch size 4: X.XX seconds

=== 3. Running Advanced Image Transformations ===

Advanced Operations Timing:
Gaussian Blur: X.XX seconds
Edge Detection: X.XX seconds
```

## Analyzing and Comparing Results

After both benchmarks complete, use these guidelines to compare performance:

1. **Direct Like-for-Like Comparison**:
   - Compare execution times for identical operations (same image/matrix sizes)
   - Calculate speedup factor: CPU time / GPU time for each operation

2. **Scaling Analysis**:
   - How does processing time increase as image size grows? (2048×2048 → 4096×4096)
   - How does processing time increase as batch size grows? (1 → 2 → 4)
   - Does GPU show better scaling characteristics than CPU?

3. **Cost Efficiency Analysis**:
   - Get the instance hourly rates from AWS pricing
   - Calculate: (CPU instance price × CPU time) / (GPU instance price × GPU time)
   - If result > 1: GPU is more cost-efficient
   - If result < 1: CPU is more cost-efficient

4. **Operation-Specific Performance**:
   - Do certain operations benefit more from GPU acceleration?
   - Which operations show the highest speedup factors?

## Creating Performance Comparison Tables

After running the benchmarks, create comparison tables like these:

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

## Cleaning Up

To avoid ongoing charges, delete all resources:

```bash
aws cloudformation delete-stack --stack-name gpu-benchmark
```

This will delete all resources including VPC, IAM roles, and AWS Batch resources.

## Troubleshooting

### Compute Environment Issues

If the compute environment shows "INVALID" status:

```bash
# Check compute environment status
ENV=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuComputeEnvironment'].OutputValue" --output text 2>/dev/null || echo "Not found")
aws batch describe-compute-environments --compute-environments $ENV
```

Common issues:
- Insufficient service quota for GPU instances
- AMI not available in your region
- User data script formatting issues

### Job Submission Failures

If jobs fail to submit or get stuck in RUNNABLE state:

1. Check if compute environment is scaling up correctly:
   ```bash
   aws batch describe-compute-environments --compute-environments $ENV --query "computeEnvironments[0].status"
   ```

2. Verify your instance quota is sufficient:
   ```bash
   aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
   ```

3. Check CloudWatch logs for Docker errors:
   ```bash
   aws logs describe-log-streams --log-group-name /aws/batch/gpu-benchmark
   ```

### CPU Job Timeouts

If CPU jobs time out on larger workloads:

1. Consider modifying the CPU job definition to increase the timeout:
   ```bash
   aws batch update-job-definition --job-definition cpu-image-processing-benchmark \
       --timeout attemptDurationSeconds=43200  # 12 hours
   ```

2. Alternatively, modify the benchmark script to reduce problem sizes for your specific use case

## Additional Resources

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [NVIDIA CUDA Documentation](https://docs.nvidia.com/cuda/)
- [PyTorch Documentation](https://pytorch.org/docs/)
- [EC2 GPU Instance Types](https://aws.amazon.com/ec2/instance-types/#gpu)
- [AWS GPU Optimization Best Practices](https://docs.aws.amazon.com/dlami/latest/devguide/gpu.html)

## Support

For issues and questions, please file an issue in this GitHub repository.