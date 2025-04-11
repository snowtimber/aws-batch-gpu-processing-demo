# GPU and CPU Image Processing Benchmark with AWS Batch

This repository contains an AWS SAM template that sets up GPU and CPU benchmarking environments for image processing using AWS Batch. It enables direct performance comparison between GPU-accelerated and CPU-only processing with identical workloads.

## Quick Start

Deploy the CloudFormation stack and run the benchmarks in one command:

```bash
# Deploy and run benchmarks
sam deploy \
  --template-file gpu-batch-benchmark.yaml \
  --stack-name gpu-benchmark \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset && \
  ./run-benchmarks.sh
```

This will:
1. Deploy all required AWS resources (VPC, IAM roles, AWS Batch environments)
2. Submit both GPU and CPU benchmark jobs
3. Monitor job progress until completion
4. Extract and display benchmark results

## Benchmark Results

Our benchmarks show significant performance improvements when using GPU acceleration for image processing and matrix operations:

### Performance Comparison

| Operation               | CPU Time (s)  | GPU Time (s)  | Speedup Factor |
|-------------------------|---------------|---------------|----------------|
| Matrix 1000x1000        | 0.03          | 0.34          | 0.08           |
| Matrix 5000x5000        | 0.51          | 0.01          | 51.00          |
| Matrix 8000x8000        | 1.46          | 0.04          | 36.50          |
| Matrix 10000x10000      | 2.45          | 0.09          | 27.22          |
| Image 2048x2048 (batch 1) | 0.28        | 0.15          | 1.86           |
| Image 2048x2048 (batch 2) | 0.52        | 0.04          | 13.00          |
| Image 4096x4096 (batch 1) | 0.28        | 0.15          | 1.86           |
| Image 4096x4096 (batch 2) | 2.10        | 0.22          | 9.54           |
| Gaussian Blur           | 0.09          | 0.04          | 2.25           |
| **Total Job Time**      | **10.05**     | **1.89**      | **5.31**       |

### Key Findings

- **Overall Performance**: GPU processing is 5.31x faster overall than CPU processing
- **Matrix Operations**: Extremely high speedup (up to 51x) for large matrix operations
- **Batch Processing**: Higher batch sizes show greater GPU advantage
- **Instance Types**:
  - GPU: NVIDIA A10G GPU (g5.8xlarge/g5.12xlarge)
  - CPU: r5.4xlarge/r5.8xlarge/m5.8xlarge/c5.18xlarge

## Prerequisites

Before you begin, ensure you have:

1. [AWS CLI](https://aws.amazon.com/cli/) installed and configured
2. [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) installed
3. Permissions to create IAM roles, VPC resources, EC2 instances, and AWS Batch resources
4. Sufficient quota to launch GPU instances (g5 or p3 instances)

## Deployment

### 1. Clone this repository

```bash
git clone https://github.com/yourusername/gpu-batch-benchmark.git
cd gpu-batch-benchmark
```

### 2. Deploy and run benchmarks

```bash
# Deploy stack and run benchmarks in one command
sam deploy \
  --template-file gpu-batch-benchmark.yaml \
  --stack-name gpu-benchmark \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset && \
  ./run-benchmarks.sh
```

### 3. View results

The benchmark results will be displayed in the terminal and saved to:
- `gpu-benchmark.txt`
- `cpu-benchmark.txt`
- `benchmark-summary.txt`

## Cleaning Up

To avoid ongoing charges, delete all resources:

```bash
aws cloudformation delete-stack --stack-name gpu-benchmark
```

## Troubleshooting

### Common Issues

1. **GPU Memory Issues**: If you encounter CUDA out-of-memory errors, the template uses larger GPU instances (g5.8xlarge, g5.12xlarge, p3.2xlarge) with sufficient GPU memory for the benchmark workloads.

2. **Job Execution Issues**: If jobs get stuck in RUNNABLE state, check instance availability:
   ```bash
   aws batch describe-compute-environments --query "computeEnvironments[?computeEnvironmentName.contains(@,'GPU')].{name:computeEnvironmentName,maxvCpus:computeResources.maxvCpus,desiredvCpus:computeResources.desiredvCpus}"
   ```

3. **Viewing Error Logs**: If a job fails, check its logs:
   ```bash
   LOG_STREAM=$(aws batch describe-jobs --jobs <job-id> --query "jobs[0].container.logStreamName" --output text)
   aws logs get-log-events --log-group-name /aws/batch/job --log-stream-name "$LOG_STREAM"
   ```
