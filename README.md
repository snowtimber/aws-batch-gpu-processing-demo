<!-- README.md -->
# GPU and CPU Image Processing Benchmark with AWS Batch

This repository contains an AWS SAM template that sets up GPU and CPU benchmarking environments for image processing using AWS Batch. The environment lets you compare the performance of GPU-accelerated workloads against CPU-only processing.

## Overview

The benchmark runs identical image processing operations on both GPU and CPU instances, allowing you to:

1. Compare execution times between GPU and CPU
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

### 5. Get the job submission commands

Once the deployment is complete, retrieve the commands to submit benchmark jobs:

```bash
# Get the GPU job submission command
aws cloudformation describe-stacks \
  --stack-name gpu-benchmark \
  --query "Stacks[0].Outputs[?OutputKey=='SubmitGpuJobCommand'].OutputValue" \
  --output text

# Get the CPU job submission command
aws cloudformation describe-stacks \
  --stack-name gpu-benchmark \
  --query "Stacks[0].Outputs[?OutputKey=='SubmitCpuJobCommand'].OutputValue" \
  --output text
```

### 6. Submit benchmark jobs

Execute the commands from the previous step to submit both GPU and CPU benchmark jobs:

```bash
# Submit GPU benchmark job
aws batch submit-job \
  --job-name gpu-benchmark-$(date +%Y%m%d%H%M%S) \
  --job-queue <gpu-job-queue-arn> \
  --job-definition <gpu-job-definition-arn>

# Submit CPU benchmark job
aws batch submit-job \
  --job-name cpu-benchmark-$(date +%Y%m%d%H%M%S) \
  --job-queue <cpu-job-queue-arn> \
  --job-definition <cpu-job-definition-arn>
```

Examples:

For the GPU benchmark:
```bash
aws batch submit-job --job-name gpu-benchmark-\$(date +%Y%m%d%H%M%S) --job-queue arn:aws:batch:us-east-1:730335522976:job-queue/GpuJobQueue-ah5wLDDJK0Vxglfh --job-definition arn:aws:batch:us-east-1:730335522976:job-definition/gpu-image-processing-benchmark:2
```

For the CPU benchmark:

```bash
aws batch submit-job --job-name cpu-benchmark-\$(date +%Y%m%d%H%M%S) --job-queue arn:aws:batch:us-east-1:730335522976:job-queue/CPUJobQueue-y0JUQtb8AbVVPVkn --job-definition arn:aws:batch:us-east-1:730335522976:job-definition/cpu-image-processing-benchmark:1


```

### 7. Monitor the job executions

You can monitor the job status using the AWS Batch console or via the CLI:

```bash
# List all jobs in the GPU queue
aws batch list-jobs --job-queue <gpu-job-queue-arn> --status RUNNING

# List all jobs in the CPU queue
aws batch list-jobs --job-queue <cpu-job-queue-arn> --status RUNNING

# Get details about a specific job
aws batch describe-jobs --jobs <job-id>
```

### 8. View job logs

Job logs are stored in CloudWatch Logs. You can view them in the CloudWatch console or via the CLI:

```bash
# Get the log stream name
LOG_STREAM=$(aws batch describe-jobs --jobs <job-id> --query "jobs[0].container.logStreamName" --output text)

# View the logs
aws logs get-log-events --log-group-name /aws/batch/gpu-benchmark --log-stream-name $LOG_STREAM
```

## Understanding the GPU and CPU Benchmarks

Both benchmarks perform the same operations with suitable adjustments for hardware capability:

### GPU Benchmark

1. **Matrix Operations**: Tests 5000×5000 to 15000×15000 matrices
2. **Image Processing**: Processes 4096×4096 and 8192×8192 images with batch sizes of 1, 4, and 8
3. **Advanced Image Transformations**: Implements Gaussian blur and edge detection

### CPU Benchmark

1. **Matrix Operations**: Tests 1000×1000 to 5000×5000 matrices (smaller due to CPU limitations)
2. **Image Processing**: Processes 2048×2048 and 4096×4096 images with batch sizes of 1, 2, and 4
3. **Advanced Image Transformations**: Implements the same Gaussian blur and edge detection on smaller images

## Analyzing Results

After running both benchmarks, you can compare:

1. **Raw Performance**: Compare execution times for similar operations
2. **Speedup Factor**: Calculate GPU speedup = CPU time / GPU time
3. **Cost Efficiency**: Calculate (CPU instance cost × CPU time) / (GPU instance cost × GPU time)

For most image processing operations, you should typically see:
- 10-100× speedup for matrix operations
- 5-30× speedup for convolutional operations
- 3-20× speedup for complex transformations

## Cleaning Up

To delete all resources created by this template:

```bash
aws cloudformation delete-stack --stack-name gpu-benchmark
```

This will delete all resources including VPC, IAM roles, and AWS Batch resources.

## Troubleshooting

### Instance Launch Issues

If instances fail to launch:

1. Check your service quotas for GPU instance types
2. Verify that the AMI ID is valid for your region
3. Check the AWS Batch event logs for specific error messages:
   ```bash
   aws batch describe-compute-environments --compute-environments <compute-env-arn> --query "computeEnvironments[0].status"
   ```

### Job Failure Issues

If jobs fail to complete:

1. Check CloudWatch Logs for error messages
2. For GPU jobs, verify that the NVIDIA drivers are properly installed (look for `nvidia-smi` output in the logs)
3. Ensure the container has access to the GPU device

### Resource Limitations

If you encounter resource limitations:

1. Reduce the `MaxvCpus` parameter in the template
2. Choose smaller instance types
3. Request quota increases for your AWS account

## Understanding the Internet Gateway

The Internet Gateway (IGW) in the template is essential for:

1. **Package Downloads**: Enabling EC2 instances to download packages via `apt-get` and `pip`
2. **Container Image Pulls**: Allowing instances to pull Docker images from public repositories
3. **AWS Service Communication**: Facilitating communication with CloudWatch Logs and other AWS services

Without the IGW, the compute instances would not be able to access the internet to download necessary dependencies or stream logs to CloudWatch.

## Performance Evaluation Framework

To properly evaluate if GPU acceleration is beneficial for your specific workload, consider:

1. **Execution Time**: Raw processing time reduction
2. **Instance Cost**: Hourly cost difference between GPU and CPU instances
3. **Cost Efficiency Ratio**: Calculate using the formula:
   ```
   Efficiency = (CPU price × CPU time) / (GPU price × GPU time)
   ```
   - If > 1: GPU is more cost-efficient
   - If < 1: CPU is more cost-efficient

4. **Scaling Properties**: How performance changes with increasing problem size
   - If speedup increases with problem size, GPUs become more cost-effective for larger workloads

## Additional Resources

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [NVIDIA CUDA Documentation](https://docs.nvidia.com/cuda/)
- [PyTorch Documentation](https://pytorch.org/docs/)
- [EC2 GPU Instance Types](https://aws.amazon.com/ec2/instance-types/#gpu)
- [AWS GPU Optimization Best Practices](https://docs.aws.amazon.com/dlami/latest/devguide/gpu.html)

## Support

For issues and questions, please file an issue in this GitHub repository.