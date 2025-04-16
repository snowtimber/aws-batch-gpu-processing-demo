# AWS Batch Job Submission Tool

This tool provides a flexible way to submit jobs to AWS Batch with support for different job definitions, job queues, and parameters. It can submit single jobs or multiple jobs in batch.

## Features

- Submit jobs to AWS Batch with different job definitions
- Support for both GPU and CPU job queues
- Set custom job parameters (environment variables, command overrides, etc.)
- Submit multiple jobs at once using a configuration file
- Create job dependency chains
- Monitor job status after submission

## Prerequisites

- Python 3.6+
- AWS CLI configured with appropriate permissions
- Boto3 library (`pip install boto3`)

## Installation

1. Download the script:
   ```
   chmod +x submit-batch-jobs.py
   ```

2. Ensure you have the required Python packages:
   ```
   pip install boto3
   ```

## Usage

### Command Line Arguments

The script supports the following command line arguments:

#### Job Definition and Queue Options
- `--job-definition`: Job definition name or ARN
- `--job-queue`: Job queue name or ARN
- `--job-name`: Name for the job

#### Configuration File Option
- `--config`: Path to JSON configuration file for batch job submission

#### Job Parameters
- `--command`: Command override for the job
- `--env`: Environment variables in format "KEY1=value1,KEY2=value2"
- `--memory`: Memory override in MB
- `--vcpus`: vCPUs override
- `--gpu`: Number of GPUs to use
- `--timeout`: Timeout in seconds

#### Batch Options
- `--count`: Number of identical jobs to submit (default: 1)
- `--depends-on`: Job IDs this job depends on, comma separated
- `--array-size`: Size of the job array

#### Output Options
- `--output`: Output file for job IDs
- `--monitor`: Monitor job status after submission
- `--region`: AWS region
- `--profile`: AWS profile name

### Examples

#### Submit a Single Job

```bash
python submit-batch-jobs.py \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --job-name my-gpu-job
```

#### Submit a Job with Environment Variables

```bash
python submit-batch-jobs.py \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --env "MODEL_TYPE=resnet,BATCH_SIZE=32"
```

#### Submit Multiple Jobs from a Config File

```bash
python submit-batch-jobs.py --config batch-jobs.json
```

#### Submit Multiple Identical Jobs

```bash
python submit-batch-jobs.py \
  --job-definition cpu-image-processing-benchmark \
  --job-queue CPUJobQueue \
  --job-name cpu-benchmark \
  --count 5
```

#### Submit a Job with Dependencies

```bash
python submit-batch-jobs.py \
  --job-definition gpu-image-processing-benchmark \
  --job-queue GpuJobQueue \
  --job-name dependent-job \
  --depends-on "job-id-1,job-id-2"
```

#### Monitor Job Status After Submission

```bash
python submit-batch-jobs.py \
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

### Job Dependencies in Configuration

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
