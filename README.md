# GPU-Accelerated Image Processing Benchmark with AWS Batch

This repository contains an AWS SAM template that sets up a GPU-accelerated image processing benchmark environment using AWS Batch. The environment is fully self-contained and optimized for high-performance GPU workloads.

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

You may also want to update the AMI ID in the `GpuComputeEnvironment` resource to use the latest NVIDIA GPU-Optimized AMI available in your region.

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
- AWS Batch compute environment and job queue
- GPU-optimized job definition

### 4. Monitor deployment progress

You can monitor the deployment in the AWS CloudFormation console or via the CLI:

```bash
aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].StackStatus"
```

Wait until the deployment status is `CREATE_COMPLETE`.

### 5. Get the job submission command

Once the deployment is complete, retrieve the command to submit a benchmark job:

```bash
aws cloudformation describe-stacks \
  --stack-name gpu-benchmark \
  --query "Stacks[0].Outputs[?OutputKey=='SubmitJobCommand'].OutputValue" \
  --output text
```

### 6. Submit a benchmark job

Copy the command from the previous step and execute it to submit a benchmark job:

```bash
aws batch submit-job \
  --job-name gpu-benchmark-$(date +%Y%m%d%H%M%S) \
  --job-queue <job-queue-arn> \
  --job-definition <job-definition-arn>
```

### 7. Monitor the job execution

You can monitor the job status using the AWS Batch console or via the CLI:

```bash
# List all jobs
aws batch list-jobs --job-queue <job-queue-arn> --status RUNNING

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

## Understanding the GPU Benchmark

The benchmark job performs several tests to measure GPU performance:

1. **Matrix Operations**: Tests GPU performance with matrix multiplications of varying sizes.
2. **Image Processing**: Processes synthetic images of different sizes with various batch sizes.
3. **Advanced Image Transformations**: Implements advanced image operations like Gaussian blur and edge detection.

Results are printed to the job logs and include timing information for each operation.

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
2. Verify that the NVIDIA drivers are properly installed (look for `nvidia-smi` output in the logs)
3. Ensure the container has access to the GPU device

### Permission Issues

If you encounter permission issues:

1. Make sure you have the necessary IAM permissions
2. Verify that the service roles have the correct policies
3. Check if the job role has the right permissions for your tasks

## Additional Resources

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [NVIDIA CUDA Documentation](https://docs.nvidia.com/cuda/)
- [PyTorch Documentation](https://pytorch.org/docs/)

## Support

For issues and questions, please file an issue in this GitHub repository.