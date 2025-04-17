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

## Setting Up AWS Batch Infrastructure

Before submitting jobs, you need to set up the AWS Batch infrastructure components:

1. Create compute environments
2. Create scheduling policies (optional)
3. Create job queues
4. Register job definitions
5. Submit jobs

### 1. Creating Compute Environments

Compute environments define the compute resources (EC2 instances) that will run your batch jobs.

#### a. Managed EC2 Compute Environment (CPU)

```bash
# Create a JSON configuration file for a CPU compute environment
cat > cpu-compute-env.json << EOF
{
  "computeEnvironmentName": "cpu-compute-environment",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 256,
    "desiredvCpus": 0,
    "instanceTypes": [
      "c5", "m5", "r5"
    ],
    "subnets": [
      "subnet-12345678",
      "subnet-23456789",
      "subnet-34567890"
    ],
    "securityGroupIds": [
      "sg-12345678"
    ],
    "instanceRole": "ecsInstanceRole",
    "tags": {
      "Name": "AWS Batch CPU Instance",
      "Environment": "Production"
    }
  },
  "serviceRole": "AWSBatchServiceRole"
}
EOF

# Create the compute environment
aws batch create-compute-environment --cli-input-json file://cpu-compute-env.json
```

#### b. Managed EC2 Compute Environment (GPU)

```bash
# Create a JSON configuration file for a GPU compute environment
cat > gpu-compute-env.json << EOF
{
  "computeEnvironmentName": "gpu-compute-environment",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 256,
    "desiredvCpus": 0,
    "instanceTypes": [
      "g4dn", "g5", "p3"
    ],
    "subnets": [
      "subnet-12345678",
      "subnet-23456789",
      "subnet-34567890"
    ],
    "securityGroupIds": [
      "sg-12345678"
    ],
    "instanceRole": "ecsInstanceRole",
    "tags": {
      "Name": "AWS Batch GPU Instance",
      "Environment": "Production"
    }
  },
  "serviceRole": "AWSBatchServiceRole"
}
EOF

# Create the compute environment
aws batch create-compute-environment --cli-input-json file://gpu-compute-env.json
```

#### c. Managed EC2 Spot Compute Environment (Cost Optimization)

```bash
# Create a JSON configuration file for a Spot compute environment
cat > spot-compute-env.json << EOF
{
  "computeEnvironmentName": "spot-compute-environment",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "SPOT",
    "allocationStrategy": "SPOT_CAPACITY_OPTIMIZED",
    "minvCpus": 0,
    "maxvCpus": 512,
    "desiredvCpus": 0,
    "instanceTypes": [
      "optimal"
    ],
    "bidPercentage": 70,
    "spotIamFleetRole": "arn:aws:iam::123456789012:role/AmazonEC2SpotFleetRole",
    "subnets": [
      "subnet-12345678",
      "subnet-23456789",
      "subnet-34567890"
    ],
    "securityGroupIds": [
      "sg-12345678"
    ],
    "instanceRole": "ecsInstanceRole",
    "tags": {
      "Name": "AWS Batch Spot Instance",
      "Environment": "Production"
    }
  },
  "serviceRole": "AWSBatchServiceRole"
}
EOF

# Create the compute environment
aws batch create-compute-environment --cli-input-json file://spot-compute-env.json
```

#### d. Unmanaged Compute Environment (For Self-Provisioned EC2 Instances or Auto Scaling Groups)

Unmanaged compute environments allow you to use your own EC2 instances or Auto Scaling Groups with AWS Batch, giving you complete control over the infrastructure.

```bash
# Create a JSON configuration file for an unmanaged compute environment
cat > unmanaged-compute-env.json << EOF
{
  "computeEnvironmentName": "unmanaged-compute-environment",
  "type": "UNMANAGED",
  "state": "ENABLED",
  "serviceRole": "AWSBatchServiceRole",
  "tags": {
    "Name": "Self-Managed Batch Environment",
    "Purpose": "Custom GPU Processing",
    "ManagedBy": "Infrastructure Team"
  }
}
EOF

# Create the compute environment
aws batch create-compute-environment --cli-input-json file://unmanaged-compute-env.json

# Get the ECS cluster name created by AWS Batch (needed for instance configuration)
ECS_CLUSTER_NAME=$(aws batch describe-compute-environments \
  --compute-environments unmanaged-compute-environment \
  --query "computeEnvironments[0].ecsClusterArn" \
  --output text | cut -d'/' -f2)

echo "ECS Cluster Name for instance configuration: $ECS_CLUSTER_NAME"
```

**How Unmanaged Compute Environments Work:**

When you create an unmanaged compute environment, AWS Batch:
1. Creates an Amazon ECS cluster with the same name as your compute environment
2. Does NOT provision or manage any EC2 instances
3. Expects you to provide and manage the instances yourself

To connect your self-provisioned EC2 instances or Auto Scaling Group to this environment:

1. Install the Amazon ECS container agent on your instances
2. Configure the agent to register with the ECS cluster created by AWS Batch
3. Set the following in `/etc/ecs/ecs.config` on your instances:
   ```
   ECS_CLUSTER=your-batch-created-cluster-name
   ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]
   ECS_ENABLE_TASK_IAM_ROLE=true
   ```
4. For GPU instances, also add: `ECS_ENABLE_GPU_SUPPORT=true`

Your instances must have:
- IAM role with permissions for ECS and any resources your jobs need
- Proper networking configuration to communicate with AWS services
- Docker installed and configured

AWS Batch will then schedule jobs on your instances based on the resources they report to ECS.

### 2. Creating Scheduling Policies

Scheduling policies allow you to configure fair share scheduling across different users or groups.

```bash
# Create a JSON configuration file for a scheduling policy
cat > scheduling-policy.json << EOF
{
  "name": "enterprise-fair-share",
  "fairsharePolicy": {
    "shareDecaySeconds": 3600,
    "computeReservation": 5,
    "shareDistribution": [
      {
        "shareIdentifier": "research-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "engineering-team",
        "weightFactor": 2.0
      },
      {
        "shareIdentifier": "data-science-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "default",
        "weightFactor": 1.0
      }
    ]
  }
}
EOF

# Create the scheduling policy
aws batch create-scheduling-policy --cli-input-json file://scheduling-policy.json
```

### 3. Creating Job Queues

Job queues store jobs until they can be scheduled to run in a compute environment.

#### a. Basic Job Queue

```bash
# Create a JSON configuration file for a basic job queue
cat > basic-job-queue.json << EOF
{
  "jobQueueName": "standard-job-queue",
  "state": "ENABLED",
  "priority": 10,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "cpu-compute-environment"
    },
    {
      "order": 2,
      "computeEnvironment": "spot-compute-environment"
    }
  ]
}
EOF

# Create the job queue
aws batch create-job-queue --cli-input-json file://basic-job-queue.json
```

#### b. GPU Job Queue

```bash
# Create a JSON configuration file for a GPU job queue
cat > gpu-job-queue.json << EOF
{
  "jobQueueName": "gpu-job-queue",
  "state": "ENABLED",
  "priority": 20,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "gpu-compute-environment"
    }
  ]
}
EOF

# Create the job queue
aws batch create-job-queue --cli-input-json file://gpu-job-queue.json
```

#### c. Job Queue with Scheduling Policy

```bash
# Create a JSON configuration file for a job queue with scheduling policy
cat > fair-share-job-queue.json << EOF
{
  "jobQueueName": "fair-share-job-queue",
  "state": "ENABLED",
  "priority": 10,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "cpu-compute-environment"
    },
    {
      "order": 2,
      "computeEnvironment": "spot-compute-environment"
    }
  ],
  "schedulingPolicyArn": "arn:aws:batch:us-west-2:123456789012:scheduling-policy/enterprise-fair-share"
}
EOF

# Create the job queue
aws batch create-job-queue --cli-input-json file://fair-share-job-queue.json
```

#### d. Team-Specific Job Queues

```bash
# Create job queues for different teams
for team in research engineering data-science; do
  cat > ${team}-job-queue.json << EOF
  {
    "jobQueueName": "${team}-job-queue",
    "state": "ENABLED",
    "priority": 10,
    "computeEnvironmentOrder": [
      {
        "order": 1,
        "computeEnvironment": "cpu-compute-environment"
      },
      {
        "order": 2,
        "computeEnvironment": "spot-compute-environment"
      }
    ],
    "schedulingPolicyArn": "arn:aws:batch:us-west-2:123456789012:scheduling-policy/enterprise-fair-share",
    "tags": {
      "Team": "${team}",
      "Department": "Technology"
    }
  }
EOF

  # Create the job queue
  aws batch create-job-queue --cli-input-json file://${team}-job-queue.json
  echo "${team} job queue created"
done
```

### 4. Complete End-to-End Infrastructure Setup

Here's a complete example that sets up the entire AWS Batch infrastructure:

```bash
#!/bin/bash
# AWS Batch Infrastructure Setup

# Set variables
AWS_REGION="us-west-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:3].SubnetId' --output json | jq -c .)
SECURITY_GROUP=$(aws ec2 create-security-group --group-name "batch-sg" --description "Security group for AWS Batch" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Allow the security group to access internet
aws ec2 authorize-security-group-egress --group-id $SECURITY_GROUP --protocol all --port all --cidr 0.0.0.0/0

# 1. Create compute environments
echo "Creating compute environments..."

# CPU compute environment
cat > cpu-compute-env.json << EOF
{
  "computeEnvironmentName": "cpu-compute-environment",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 256,
    "desiredvCpus": 0,
    "instanceTypes": ["optimal"],
    "subnets": $SUBNETS,
    "securityGroupIds": ["$SECURITY_GROUP"],
    "instanceRole": "ecsInstanceRole",
    "tags": {
      "Name": "AWS Batch CPU Instance"
    }
  },
  "serviceRole": "AWSBatchServiceRole"
}
EOF

aws batch create-compute-environment --cli-input-json file://cpu-compute-env.json

# GPU compute environment
cat > gpu-compute-env.json << EOF
{
  "computeEnvironmentName": "gpu-compute-environment",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 256,
    "desiredvCpus": 0,
    "instanceTypes": ["g4dn", "g5", "p3"],
    "subnets": $SUBNETS,
    "securityGroupIds": ["$SECURITY_GROUP"],
    "instanceRole": "ecsInstanceRole",
    "tags": {
      "Name": "AWS Batch GPU Instance"
    }
  },
  "serviceRole": "AWSBatchServiceRole"
}
EOF

aws batch create-compute-environment --cli-input-json file://gpu-compute-env.json

# 2. Create scheduling policy
echo "Creating scheduling policy..."

cat > scheduling-policy.json << EOF
{
  "name": "enterprise-fair-share",
  "fairsharePolicy": {
    "shareDecaySeconds": 3600,
    "computeReservation": 5,
    "shareDistribution": [
      {
        "shareIdentifier": "research-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "engineering-team",
        "weightFactor": 2.0
      },
      {
        "shareIdentifier": "data-science-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "default",
        "weightFactor": 1.0
      }
    ]
  }
}
EOF

aws batch create-scheduling-policy --cli-input-json file://scheduling-policy.json
POLICY_ARN="arn:aws:batch:$AWS_REGION:$ACCOUNT_ID:scheduling-policy/enterprise-fair-share"

# 3. Create job queues
echo "Creating job queues..."

# Standard CPU queue
cat > cpu-job-queue.json << EOF
{
  "jobQueueName": "cpu-job-queue",
  "state": "ENABLED",
  "priority": 10,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "cpu-compute-environment"
    }
  ],
  "schedulingPolicyArn": "$POLICY_ARN"
}
EOF

aws batch create-job-queue --cli-input-json file://cpu-job-queue.json

# GPU queue
cat > gpu-job-queue.json << EOF
{
  "jobQueueName": "gpu-job-queue",
  "state": "ENABLED",
  "priority": 20,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "gpu-compute-environment"
    }
  ],
  "schedulingPolicyArn": "$POLICY_ARN"
}
EOF

aws batch create-job-queue --cli-input-json file://gpu-job-queue.json

echo "AWS Batch infrastructure setup complete!"
```

### 5. Managing AWS Batch Infrastructure

#### a. Updating a Compute Environment

```bash
# Update a compute environment (e.g., change the desired vCPUs)
cat > update-compute-env.json << EOF
{
  "computeEnvironment": "cpu-compute-environment",
  "state": "ENABLED",
  "computeResources": {
    "minvCpus": 0,
    "maxvCpus": 512,
    "desiredvCpus": 16
  }
}
EOF

aws batch update-compute-environment --cli-input-json file://update-compute-env.json
```

#### b. Updating a Job Queue

```bash
# Update a job queue (e.g., change the priority)
cat > update-job-queue.json << EOF
{
  "jobQueue": "cpu-job-queue",
  "state": "ENABLED",
  "priority": 15,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "cpu-compute-environment"
    }
  ]
}
EOF

aws batch update-job-queue --cli-input-json file://update-job-queue.json
```

#### c. Updating a Scheduling Policy

```bash
# Update a scheduling policy (e.g., add a new team)
cat > update-scheduling-policy.json << EOF
{
  "name": "enterprise-fair-share",
  "fairsharePolicy": {
    "shareDecaySeconds": 3600,
    "computeReservation": 5,
    "shareDistribution": [
      {
        "shareIdentifier": "research-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "engineering-team",
        "weightFactor": 2.0
      },
      {
        "shareIdentifier": "data-science-team",
        "weightFactor": 3.0
      },
      {
        "shareIdentifier": "marketing-team",
        "weightFactor": 1.5
      },
      {
        "shareIdentifier": "default",
        "weightFactor": 1.0
      }
    ]
  }
}
EOF

aws batch update-scheduling-policy --cli-input-json file://update-scheduling-policy.json
```

#### d. Deleting Resources

```bash
# Delete resources in the correct order
# 1. Delete job queues
aws batch update-job-queue --job-queue cpu-job-queue --state DISABLED
aws batch update-job-queue --job-queue gpu-job-queue --state DISABLED
aws batch delete-job-queue --job-queue cpu-job-queue
aws batch delete-job-queue --job-queue gpu-job-queue

# 2. Delete compute environments
aws batch update-compute-environment --compute-environment cpu-compute-environment --state DISABLED
aws batch update-compute-environment --compute-environment gpu-compute-environment --state DISABLED
aws batch delete-compute-environment --compute-environment cpu-compute-environment
aws batch delete-compute-environment --compute-environment gpu-compute-environment

# 3. Delete scheduling policy
aws batch delete-scheduling-policy --arn arn:aws:batch:us-west-2:123456789012:scheduling-policy/enterprise-fair-share
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
