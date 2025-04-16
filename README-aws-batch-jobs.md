# AWS Batch Job Submission Tools

This repository contains a set of tools for submitting and managing jobs on AWS Batch, with support for different job definitions, job queues, and parameters. These tools make it easy to submit single jobs or multiple jobs in batch, with various configurations.

## Overview

The AWS Batch Job Submission Tools consist of:

1. **submit-batch-jobs.py** - A Python script for submitting jobs to AWS Batch with flexible options
2. **submit-jobs.sh** - A shell script wrapper for the Python script
3. **batch-jobs-example.json** - An example configuration file for batch job submission
4. **submit-custom-job-example.sh** - An example script demonstrating how to submit custom jobs
5. **create-custom-job-definition.sh** - A script for creating custom job definitions
6. **batch-job-submission-README.md** - Detailed documentation for the Python script

## Prerequisites

- Python 3.6+
- AWS CLI configured with appropriate permissions
- Boto3 library (`pip install boto3`)
- AWS Batch environment set up (compute environments, job queues, and job definitions)

## Quick Start

### 1. Submit a Single Job

```bash
./submit-jobs.sh \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --job-name my-gpu-job
```

### 2. Submit Multiple Jobs from a Configuration File

```bash
./submit-jobs.sh --config batch-jobs-example.json
```

### 3. Create a Custom Job Definition and Submit Jobs to It

```bash
./create-custom-job-definition.sh
./submit-jobs.sh --config pytorch-jobs.json --monitor
```

## Script Descriptions

### submit-batch-jobs.py

This is the core Python script that interacts with AWS Batch using the boto3 library. It supports:

- Submitting jobs with different job definitions
- Setting custom job parameters (environment variables, command overrides, etc.)
- Submitting multiple jobs at once using a configuration file
- Creating job dependency chains
- Monitoring job status after submission

See [batch-job-submission-README.md](batch-job-submission-README.md) for detailed documentation.

### submit-jobs.sh

A shell script wrapper for `submit-batch-jobs.py` that provides a more convenient command-line interface. It supports all the same options as the Python script but with a more shell-friendly syntax.

### batch-jobs-example.json

An example configuration file that demonstrates how to define multiple jobs with different parameters in a single JSON file. This can be used with the `--config` option of either `submit-batch-jobs.py` or `submit-jobs.sh`.

### submit-custom-job-example.sh

An example script that demonstrates how to:

1. Get job queue and job definition ARNs from CloudFormation outputs
2. Submit a single GPU job with custom parameters
3. Submit multiple CPU jobs
4. Submit jobs using a configuration file

### create-custom-job-definition.sh

A script that demonstrates how to:

1. Create a custom AWS Batch job definition for specialized workloads
2. Register the job definition with AWS Batch
3. Create a configuration file for submitting jobs to the new job definition

This script also creates a sample PyTorch training script (`train.py`) and a configuration file (`pytorch-jobs.json`) for submitting jobs that use this script.

## Usage Examples

### Submit a Job with Environment Variables

```bash
./submit-jobs.sh \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --env "MODEL_TYPE=resnet,BATCH_SIZE=32"
```

### Submit Multiple Identical Jobs

```bash
./submit-jobs.sh \
  --job-definition cpu-image-processing-benchmark \
  --job-queue CPUJobQueue \
  --job-name cpu-benchmark \
  --count 5
```

### Submit a Job with Dependencies

```bash
./submit-jobs.sh \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --job-name dependent-job \
  --depends-on "job-id-1,job-id-2"
```

### Monitor Job Status After Submission

```bash
./submit-jobs.sh \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --monitor
```

## Configuration File Format

The configuration file should be in JSON format and can define either a single job or multiple jobs:

### Single Job Configuration

```json
{
  "jobDefinition": "gpu-image-processing-benchmark",
  "jobQueue": "GpuJobQueue",
  "jobName": "gpu-benchmark",
  "containerOverrides": {
    "command": ["bash", "-c", "echo 'Running custom GPU benchmark'"],
    "environment": [
      {"name": "MODEL_TYPE", "value": "resnet50"},
      {"name": "BATCH_SIZE", "value": "32"}
    ],
    "resourceRequirements": [
      {"type": "GPU", "value": "1"}
    ]
  }
}
```

### Multiple Jobs Configuration

```json
{
  "jobs": [
    {
      "jobDefinition": "gpu-image-processing-benchmark",
      "jobQueue": "GpuJobQueue",
      "jobName": "gpu-benchmark-1",
      "containerOverrides": {
        "command": ["bash", "-c", "echo 'Running custom GPU benchmark'"],
        "environment": [
          {"name": "MODEL_TYPE", "value": "resnet50"},
          {"name": "BATCH_SIZE", "value": "32"}
        ],
        "resourceRequirements": [
          {"type": "GPU", "value": "1"}
        ]
      }
    },
    {
      "jobDefinition": "cpu-image-processing-benchmark",
      "jobQueue": "CPUJobQueue",
      "jobName": "cpu-benchmark-1",
      "containerOverrides": {
        "command": ["bash", "-c", "echo 'Running custom CPU benchmark'"],
        "environment": [
          {"name": "MODEL_TYPE", "value": "mobilenet"},
          {"name": "BATCH_SIZE", "value": "64"}
        ]
      }
    }
  ]
}
```

## Job Dependencies in Configuration

You can create job dependencies within the configuration file:

```json
{
  "jobs": [
    {
      "jobDefinition": "gpu-image-processing-benchmark",
      "jobQueue": "GpuJobQueue",
      "jobName": "gpu-benchmark-1"
    },
    {
      "jobDefinition": "gpu-image-processing-benchmark",
      "jobQueue": "GpuJobQueue",
      "jobName": "gpu-benchmark-2",
      "dependsOn": [
        {"jobId": "${gpu-benchmark-1}", "type": "SEQUENTIAL"}
      ]
    }
  ]
}
```

The `${job-name}` syntax is used to reference job IDs from previously submitted jobs in the same configuration file.

## Tips

1. Use the `--monitor` flag to watch job progress after submission
2. For complex job workflows, use a configuration file instead of command line arguments
3. Use job dependencies to create sequential or parallel workflows
4. Use job arrays for parameter sweeps or batch processing
5. Store job IDs with `--output` for later reference or dependency creation

## Troubleshooting

- If jobs fail to submit, check your AWS credentials and permissions
- Ensure the job definition and job queue exist and are in the ACTIVE state
- Check that your container overrides are compatible with the job definition
- For GPU jobs, ensure the compute environment has GPU instances available
