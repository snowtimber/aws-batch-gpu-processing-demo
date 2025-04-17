# Enterprise AWS Batch Job Submission

This guide demonstrates how to use JSON-based job definitions and submissions for centralized AWS Batch compute environments.

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

### 1. Developer Creating and Submitting a Job

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

# 2. Register the job definition
./create-job-definition.sh my-job-definition.json --region us-west-2

# 3. Create a job submission JSON file
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

# 4. Submit the job
./submit-job.sh my-job-submission.json --monitor
```

### 2. Developer Submitting a Multi-Job Workflow

```bash
# Create a multi-job submission file with dependencies
cat > workflow-jobs.json << EOF
{
  "jobs": [
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
    },
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
        {"jobId": "${preprocess-dataset-42}", "type": "SEQUENTIAL"}
      ]
    },
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
        {"jobId": "${train-model-42}", "type": "SEQUENTIAL"}
      ]
    }
  ]
}
EOF

# Submit the workflow
./submit-job.sh workflow-jobs.json --monitor --output job-ids.txt
```

## Enterprise Integration Patterns

### Shared Compute Environments

```bash
# Example: Submit to specific compute environment based on team/project
cat > finance-team-job.json << EOF
{
  "jobDefinition": "risk-analysis",
  "jobQueue": "finance-team-queue",  # Maps to specific compute environment
  "jobName": "quarterly-risk-analysis",
  "containerOverrides": {
    "environment": [
      {"name": "QUARTER", "value": "Q2"},
      {"name": "YEAR", "value": "2025"}
    ]
  }
}
EOF
```

### Job Role Permissions

```json
{
  "jobDefinitionName": "s3-data-processor",
  "containerProperties": {
    "image": "data-processor:latest",
    "jobRoleArn": "arn:aws:iam::123456789012:role/DataProcessingRole",
    "environment": [
      {"name": "S3_BUCKET", "value": "restricted-data-bucket"}
    ]
  }
}
```

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
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
          ./submit-job.sh job-submission.json --output job-id.txt
```

## Best Practices

1. **Standardize Job Definitions**: Create and maintain standard job definitions for common workloads

2. **Use Environment Variables**: Pass runtime parameters via environment variables rather than hardcoding in job definitions

3. **Implement Job Tagging**: Add tags to track department, project, cost center:
   ```json
   "tags": {
     "Department": "Research",
     "Project": "GenAI",
     "CostCenter": "CC-123"
   }
   ```

4. **Set Resource Limits**: Enforce resource limits in job definitions to prevent runaway costs

5. **Implement Job Monitoring**: Use the `--monitor` flag or integrate with CloudWatch for job status alerts
