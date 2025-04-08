# AWS Batch GPU Processing Guide

This document explains how to properly configure AWS Batch for GPU processing, based on our investigation and debugging of common issues.

## Key Findings

During our investigation, we discovered several critical requirements for making AWS Batch GPU jobs work properly:

1. **ECS Agent Deadlock Issue**: The most significant issue we found was a potential deadlock in the EC2 UserData script. When the UserData script tries to start the ECS service directly, it can create a deadlock because:
   - The ECS service is configured to wait for cloud-init to complete
   - Cloud-init doesn't complete until the UserData script finishes
   - The UserData script is waiting for the ECS service to start

2. **Docker Configuration**: The Docker daemon must be properly configured to use the NVIDIA runtime.

3. **GPU Driver Issues**: The NVIDIA drivers must be properly loaded and functioning.

## Solution Components

Our solution addresses these issues with the following components:

### 1. Let AWS Batch Handle ECS Agent

The most important insight is to **NOT** try to configure or start the ECS agent from within the UserData script. Instead, we let AWS Batch handle this automatically after the UserData script completes.

From the AWS documentation:
> The systemd units for both Amazon ECS and Docker services have a directive to wait for cloud-init to finish before starting both services. The cloud-init process is not considered finished until your Amazon EC2 user data has finished running. Therefore, starting Amazon ECS or Docker via Amazon EC2 user data may cause a deadlock.

### 2. Docker Configuration for NVIDIA Runtime

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

### 3. Non-blocking Docker Restart

When restarting Docker, we use the `--no-block` option to avoid waiting for the service to fully start:

```bash
systemctl restart docker --no-block
```

### 4. ECS Agent Configuration for GPU Support

We configure the ECS agent to recognize and use the GPU by writing to `/etc/ecs/ecs.config`:

```
ECS_ENABLE_GPU_SUPPORT=true
ECS_INSTANCE_ATTRIBUTES={"GPU": "true", "GPU_TYPE": "NVIDIA_T4"}
```

### 5. NVIDIA Driver Verification

We verify that the NVIDIA drivers are properly loaded and functioning:

```bash
nvidia-smi
```

## Testing GPU Functionality

To test that the GPU is properly configured and accessible from containers:

```bash
docker run --rm --gpus all --log-driver=json-file nvidia/cuda:12.0.1-base-ubuntu22.04 nvidia-smi
```

This command should display information about the GPU if everything is configured correctly.

## Common Issues and Solutions

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

## Key Changes Made to the CloudFormation Template

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

## References

- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html)
- [ECS Agent Documentation](https://github.com/aws/amazon-ecs-agent)
- [NVIDIA Container Runtime Documentation](https://github.com/NVIDIA/nvidia-container-runtime)
- [AWS Documentation on ECS Agent Deadlock](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/bootstrap_container_instance.html)
