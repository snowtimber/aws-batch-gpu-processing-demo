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

## Enterprise Usage

For information on how to use AWS Batch in an enterprise environment, including how developers can submit jobs to centralized compute environments using JSON files, we provide two approaches:

1. **Shell Script Approach**: [Enterprise Usage Guide](enterprise-batch/ENTERPRISE-USAGE.md) - Uses shell scripts to simplify job definition and submission
2. **Pure CLI Approach**: [CLI Usage Guide](enterprise-batch/CLI-USAGE.md) - Uses AWS CLI commands directly with JSON files, without any custom scripts

Both approaches demonstrate how to enable developers across an organization to submit workloads to centralized AWS Batch compute environments.

## AWS Batch GPU Processing Guide

This section explains how to properly configure AWS Batch for GPU processing, based on our investigation and debugging of common issues.

### Key Findings

During our investigation, we discovered several critical requirements for making AWS Batch GPU jobs work properly:

1. **ECS Agent Deadlock Issue**: The most significant issue we found was a potential deadlock in the EC2 UserData script. When the UserData script tries to start the ECS service directly, it can create a deadlock because:
   - The ECS service is configured to wait for cloud-init to complete
   - Cloud-init doesn't complete until the UserData script finishes
   - The UserData script is waiting for the ECS service to start

2. **Docker Configuration**: The Docker daemon must be properly configured to use the NVIDIA runtime.

3. **GPU Driver Issues**: The NVIDIA drivers must be properly loaded and functioning.

### Solution Components

Our solution addresses these issues with the following components:

#### 1. Let AWS Batch Handle ECS Agent

The most important insight is to **NOT** try to configure or start the ECS agent from within the UserData script. Instead, we let AWS Batch handle this automatically after the UserData script completes.

From the AWS documentation:
> The systemd units for both Amazon ECS and Docker services have a directive to wait for cloud-init to finish before starting both services. The cloud-init process is not considered finished until your Amazon EC2 user data has finished running. Therefore, starting Amazon ECS or Docker via Amazon EC2 user data may cause a deadlock.

#### 2. Docker Configuration for NVIDIA Runtime

We configure Docker to use the NVIDIA runtime by default:

```json
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "/usr/bin/nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "storage-driver": "overlay2"
}
```

#### 3. Non-blocking Docker Restart

When restarting Docker, we use the `--no-block` option to avoid waiting for the service to fully start:

```bash
systemctl restart docker --no-block
```

#### 4. ECS Agent Configuration for GPU Support

We configure the ECS agent to recognize and use the GPU by writing to `/etc/ecs/ecs.config`:

```
ECS_ENABLE_GPU_SUPPORT=true
ECS_INSTANCE_ATTRIBUTES={"GPU": "true", "GPU_TYPE": "NVIDIA_T4"}
```

#### 5. NVIDIA Driver Verification

We verify that the NVIDIA drivers are properly loaded and functioning:

```bash
nvidia-smi
```

### Testing GPU Functionality

To test that the GPU is properly configured and accessible from containers:

```bash
docker run --rm --gpus all --log-driver=json-file nvidia/cuda:12.0.1-base-ubuntu22.04 nvidia-smi
```

This command should display information about the GPU if everything is configured correctly.

### Common Issues and Solutions

1. **ECS Agent Not Starting**: If the ECS agent isn't starting, check:
   - The UserData script completes successfully
   - The ECS configuration file at `/etc/ecs/ecs.config` is properly set up
   - The instance has the correct IAM role and permissions

2. **GPU Not Detected in Container**: If the GPU isn't detected in the container, check:
   - The NVIDIA drivers are properly loaded (`nvidia-smi`)
   - Docker is configured to use the NVIDIA runtime
   - The ECS agent is configured with `ECS_ENABLE_GPU_SUPPORT=true`

3. **Jobs Stuck in RUNNABLE State**: If jobs are stuck in the RUNNABLE state, check:
   - The instance has the correct IAM role and permissions
   - The job definition has the correct GPU resource requirements
   - The Docker daemon is properly configured for GPU support

### Key Changes Made to the CloudFormation Template

1. Updated Docker restart command to use non-blocking mode:
   ```bash
   systemctl restart docker --no-block
   ```

2. Ensured proper ECS agent configuration for GPU support:
   ```
   ECS_ENABLE_GPU_SUPPORT=true
   ECS_INSTANCE_ATTRIBUTES={"GPU": "true", "GPU_TYPE": "NVIDIA_T4"}
   ```

3. Added a comment to NOT set the ECS_CLUSTER parameter, as AWS Batch manages this automatically.

### References

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html)
- [ECS Agent Documentation](https://github.com/aws/amazon-ecs-agent)
- [NVIDIA Container Runtime Documentation](https://github.com/NVIDIA/nvidia-container-runtime)
- [AWS Documentation on ECS Agent Deadlock](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/bootstrap_container_instance.html)
