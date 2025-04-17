# Enterprise AWS Batch Job Submission with CLI

This guide demonstrates how to use AWS CLI commands with JSON files for centralized AWS Batch compute environments, without requiring any custom scripts.

## Centralized AWS Batch Architecture

```
┌─────────────────┐     ┌───────────────────┐     ┌─────────────────┐
│                 │     │                   │     │                 │
│  Developers     │────▶│  AWS Batch        │────▶│  Compute        │
│  (JSON configs) │     │  (Job Queues)     │     │  Environments   │
│                 │     │                   │     │                 │
└─────────────────┘     └───────────────────┘     └─────────────────┘
```

## Workflow Examples

### 1. Creating and Registering a Job Definition

```bash
# 1. Create a job definition JSON file
cat > my-job-definition.json << EOF
{
  "jobDefinitionName": "my-ml-training-job",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-west-2.amazonaws.com/ml-training:latest",
    "vcpus": 4,
    "memory": 16384,
    "command": ["python", "train.py"],
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchJobRole",
    "resourceRequirements": [
      {"type": "GPU", "value": "1"}
    ]
  }
}
EOF

# 2. Register the job definition with AWS Batch
aws batch register-job-definition --cli-input-json file://my-job-definition.json
```

### 2. Submitting a Single Job

```bash
# 1. Create a job submission JSON file
cat > my-job-submission.json << EOF
{
  "jobDefinition": "my-ml-training-job",
  "jobQueue": "ml-training-queue",
  "jobName": "train-model-experiment-42",
  "containerOverrides": {
    "environment": [
      {"name": "DATASET_S3_PATH", "value": "s3://my-datasets/experiment-42"},
      {"name": "MODEL_TYPE", "value": "resnet50"},
      {"name": "EPOCHS", "value": "10"}
    ]
  }
}
EOF

# 2. Submit the job
aws batch submit-job --cli-input-json file://my-job-submission.json

# 3. Capture the job ID for later reference (optional)
job_id=$(aws batch submit-job --cli-input-json file://my-job-submission.json --query 'jobId' --output text)
echo "Job submitted with ID: $job_id"
```

### 3. Submitting a Multi-Job Workflow with Dependencies

For workflows with job dependencies, we need to submit jobs sequentially and use the job IDs:

```bash
# 1. Submit the first job and capture its ID
cat > preprocess-job.json << EOF
{
  "jobDefinition": "data-preprocessing",
  "jobQueue": "cpu-job-queue",
  "jobName": "preprocess-dataset-42",
  "containerOverrides": {
    "environment": [
      {"name": "INPUT_S3_PATH", "value": "s3://raw-data/dataset-42"},
      {"name": "OUTPUT_S3_PATH", "value": "s3://processed-data/dataset-42"}
    ]
  }
}
EOF

preprocess_job_id=$(aws batch submit-job --cli-input-json file://preprocess-job.json --query 'jobId' --output text)
echo "Preprocessing job submitted with ID: $preprocess_job_id"

# 2. Create and submit the training job that depends on the preprocessing job
cat > training-job.json << EOF
{
  "jobDefinition": "model-training",
  "jobQueue": "gpu-job-queue",
  "jobName": "train-model-42",
  "containerOverrides": {
    "environment": [
      {"name": "DATASET_S3_PATH", "value": "s3://processed-data/dataset-42"},
      {"name": "MODEL_S3_PATH", "value": "s3://models/model-42"}
    ],
    "resourceRequirements": [
      {"type": "GPU", "value": "2"}
    ]
  },
  "dependsOn": [
    {"jobId": "$preprocess_job_id", "type": "SEQUENTIAL"}
  ]
}
EOF

training_job_id=$(aws batch submit-job --cli-input-json file://training-job.json --query 'jobId' --output text)
echo "Training job submitted with ID: $training_job_id"

# 3. Create and submit the evaluation job that depends on the training job
cat > evaluation-job.json << EOF
{
  "jobDefinition": "model-evaluation",
  "jobQueue": "cpu-job-queue",
  "jobName": "evaluate-model-42",
  "containerOverrides": {
    "environment": [
      {"name": "MODEL_S3_PATH", "value": "s3://models/model-42"},
      {"name": "EVAL_S3_PATH", "value": "s3://evaluations/model-42"}
    ]
  },
  "dependsOn": [
    {"jobId": "$training_job_id", "type": "SEQUENTIAL"}
  ]
}
EOF

evaluation_job_id=$(aws batch submit-job --cli-input-json file://evaluation-job.json --query 'jobId' --output text)
echo "Evaluation job submitted with ID: $evaluation_job_id"
```

### 4. Monitoring Job Status

```bash
# Check status of a specific job
aws batch describe-jobs --jobs $job_id

# Extract just the status
aws batch describe-jobs --jobs $job_id --query 'jobs[0].status' --output text

# Monitor a job until completion
job_id="your-job-id"
while true; do
  status=$(aws batch describe-jobs --jobs $job_id --query 'jobs[0].status' --output text)
  echo "$(date): Job status: $status"
  if [[ "$status" == "SUCCEEDED" || "$status" == "FAILED" ]]; then
    break
  fi
  sleep 30
done

# Monitor multiple jobs
job_ids=("job-id-1" "job-id-2" "job-id-3")
while true; do
  all_completed=true
  for job_id in "${job_ids[@]}"; do
    status=$(aws batch describe-jobs --jobs $job_id --query 'jobs[0].status' --output text)
    echo "$(date): Job $job_id status: $status"
    if [[ "$status" != "SUCCEEDED" && "$status" != "FAILED" ]]; then
      all_completed=false
    fi
  done
  
  if $all_completed; then
    echo "All jobs completed"
    break
  fi
  
  sleep 30
done
```

### 5. Using Job Arrays for Parameter Sweeps

```bash
# Create a job array submission
cat > job-array.json << EOF
{
  "jobDefinition": "parameter-sweep",
  "jobQueue": "compute-queue",
  "jobName": "hyperparameter-sweep",
  "arrayProperties": {
    "size": 10
  },
  "containerOverrides": {
    "environment": [
      {"name": "EXPERIMENT_BASE", "value": "s3://experiments/sweep-42"}
    ]
  }
}
EOF

# Submit the job array
array_job_id=$(aws batch submit-job --cli-input-json file://job-array.json --query 'jobId' --output text)
echo "Job array submitted with ID: $array_job_id"
```

## Enterprise Integration Patterns

### 1. Team-Specific Job Queues

Different teams can submit to their dedicated job queues that map to specific compute environments:

```bash
# Finance team job submission
cat > finance-job.json << EOF
{
  "jobDefinition": "risk-analysis",
  "jobQueue": "finance-team-queue",
  "jobName": "quarterly-risk-analysis",
  "containerOverrides": {
    "environment": [
      {"name": "QUARTER", "value": "Q2"},
      {"name": "YEAR", "value": "2025"}
    ]
  }
}
EOF

aws batch submit-job --cli-input-json file://finance-job.json
```

### 2. Job Role Permissions

Control access to resources through job-specific IAM roles:

```bash
# Job definition with specific IAM role
cat > secure-job-definition.json << EOF
{
  "jobDefinitionName": "s3-data-processor",
  "type": "container",
  "containerProperties": {
    "image": "data-processor:latest",
    "jobRoleArn": "arn:aws:iam::123456789012:role/DataProcessingRole",
    "environment": [
      {"name": "S3_BUCKET", "value": "restricted-data-bucket"}
    ]
  }
}
EOF

aws batch register-job-definition --cli-input-json file://secure-job-definition.json
```

### 3. CI/CD Integration

Example GitHub Actions workflow using AWS CLI commands:

```yaml
name: Submit AWS Batch Job

on:
  push:
    branches: [ main ]

jobs:
  submit-batch-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      
      - name: Submit job
        run: |
          cat > job-submission.json << EOF
          {
            "jobDefinition": "ci-test-job",
            "jobQueue": "ci-job-queue",
            "jobName": "ci-test-${{ github.sha }}",
            "containerOverrides": {
              "environment": [
                {"name": "COMMIT_SHA", "value": "${{ github.sha }}"},
                {"name": "REPO_NAME", "value": "${{ github.repository }}"}
              ]
            }
          }
          EOF
          aws batch submit-job --cli-input-json file://job-submission.json
```

### 4. Job Tagging for Cost Allocation

Add tags to track department, project, and cost center:

```bash
# Job submission with tags
cat > tagged-job.json << EOF
{
  "jobDefinition": "data-analytics",
  "jobQueue": "analytics-queue",
  "jobName": "monthly-report",
  "tags": {
    "Department": "Research",
    "Project": "GenAI",
    "CostCenter": "CC-123"
  }
}
EOF

aws batch submit-job --cli-input-json file://tagged-job.json
```

### 5. Batch Job Cancellation

Cancel running jobs when needed:

```bash
# Cancel a specific job
aws batch cancel-job --job-id $job_id --reason "No longer needed"

# Cancel all jobs in a specific job queue with a specific status
job_ids=$(aws batch list-jobs --job-queue my-queue --job-status RUNNABLE --query 'jobSummaryList[].jobId' --output text)
for job_id in $job_ids; do
  aws batch cancel-job --job-id $job_id --reason "Queue maintenance"
done
```

## Best Practices

1. **Standardize Job Definitions**: Create and maintain standard job definitions for common workloads

2. **Use Environment Variables**: Pass runtime parameters via environment variables rather than hardcoding in job definitions

3. **Implement Job Tagging**: Add tags to track department, project, cost center for better cost allocation

4. **Set Resource Limits**: Enforce resource limits in job definitions to prevent runaway costs

5. **Use Job Arrays**: For parameter sweeps or batch processing of similar tasks

6. **Implement Monitoring**: Set up CloudWatch alarms for job failures or long-running jobs

7. **Store Job IDs**: Save job IDs to a file or database for later reference or dependency tracking

8. **Use Job Dependencies**: Chain jobs together for complex workflows

9. **Leverage Job Queues**: Use different job queues for different priorities or compute requirements

10. **Document JSON Templates**: Maintain a library of JSON templates for common job types
