#!/bin/bash
# Script to create a custom AWS Batch job definition and submit jobs to it
# This demonstrates how to create a new job definition for specialized workloads

set -e

echo "=== Creating Custom AWS Batch Job Definition ==="

# Get the job role ARN from the existing CloudFormation stack
echo "Getting job role ARN from CloudFormation..."
JOB_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Resources[?LogicalResourceId=='JobRole'].PhysicalResourceId" --output text 2>/dev/null || echo "")

if [ -z "$JOB_ROLE_ARN" ]; then
    # If we couldn't get it directly from resources, try to get it from the existing job definition
    echo "Getting job role ARN from existing job definition..."
    GPU_JOB_DEF=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuJobDefinition'].OutputValue" --output text)
    JOB_ROLE_ARN=$(aws batch describe-job-definitions --job-definitions "$GPU_JOB_DEF" --query "jobDefinitions[0].containerProperties.jobRoleArn" --output text)
fi

echo "Job Role ARN: $JOB_ROLE_ARN"

# Create a temporary JSON file for the job definition
JOB_DEF_FILE="custom-job-definition.json"

cat > "$JOB_DEF_FILE" << EOF
{
    "jobDefinitionName": "custom-pytorch-training",
    "type": "container",
    "containerProperties": {
        "image": "pytorch/pytorch:2.0.0-cuda11.7-cudnn8-runtime",
        "vcpus": 8,
        "memory": 32768,
        "command": [
            "python",
            "train.py",
            "--epochs",
            "10",
            "--batch-size",
            "64"
        ],
        "jobRoleArn": "$JOB_ROLE_ARN",
        "resourceRequirements": [
            {
                "type": "GPU",
                "value": "1"
            }
        ],
        "environment": [
            {
                "name": "DATASET",
                "value": "imagenet"
            },
            {
                "name": "MODEL",
                "value": "resnet50"
            }
        ]
    },
    "timeout": {
        "attemptDurationSeconds": 7200
    },
    "retryStrategy": {
        "attempts": 2
    }
}
EOF

# Register the job definition
echo "Registering custom job definition..."
JOB_DEF_ARN=$(aws batch register-job-definition --cli-input-json file://$JOB_DEF_FILE --query 'jobDefinitionArn' --output text)
echo "Job Definition ARN: $JOB_DEF_ARN"

# Get the job queue ARN
echo "Getting GPU job queue ARN from CloudFormation..."
GPU_JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name gpu-benchmark --query "Stacks[0].Outputs[?OutputKey=='GpuJobQueue'].OutputValue" --output text)
echo "GPU Job Queue: $GPU_JOB_QUEUE"

# Create a Python script that will be used by the job
TRAIN_SCRIPT="train.py"

cat > "$TRAIN_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Simple PyTorch training script for demonstration purposes.
This would be uploaded to S3 and downloaded by the container in a real scenario.
"""
import argparse
import os
import time
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.models as models

def parse_args():
    parser = argparse.ArgumentParser(description='PyTorch Training Example')
    parser.add_argument('--epochs', type=int, default=10, help='number of epochs')
    parser.add_argument('--batch-size', type=int, default=64, help='batch size')
    parser.add_argument('--learning-rate', type=float, default=0.01, help='learning rate')
    return parser.parse_args()

def main():
    args = parse_args()
    
    # Print environment information
    print("=== Training Environment ===")
    print(f"PyTorch version: {torch.__version__}")
    print(f"CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"CUDA device: {torch.cuda.get_device_name(0)}")
    print(f"Dataset: {os.environ.get('DATASET', 'unknown')}")
    print(f"Model: {os.environ.get('MODEL', 'unknown')}")
    print(f"Epochs: {args.epochs}")
    print(f"Batch size: {args.batch_size}")
    print(f"Learning rate: {args.learning_rate}")
    
    # Create a model
    print("\n=== Creating model ===")
    model_name = os.environ.get('MODEL', 'resnet50')
    if model_name == 'resnet50':
        model = models.resnet50(pretrained=False)
    elif model_name == 'resnet18':
        model = models.resnet18(pretrained=False)
    else:
        print(f"Unknown model: {model_name}, using resnet50")
        model = models.resnet50(pretrained=False)
    
    # Move model to GPU if available
    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
    model.to(device)
    print(f"Using device: {device}")
    
    # Create optimizer
    optimizer = optim.SGD(model.parameters(), lr=args.learning_rate, momentum=0.9)
    criterion = nn.CrossEntropyLoss()
    
    # Simulate training
    print("\n=== Starting training ===")
    for epoch in range(args.epochs):
        start_time = time.time()
        running_loss = 0.0
        
        # Simulate batch processing
        for i in range(100):  # Simulate 100 batches per epoch
            # Generate random data
            inputs = torch.randn(args.batch_size, 3, 224, 224).to(device)
            labels = torch.randint(0, 1000, (args.batch_size,)).to(device)
            
            # Zero the parameter gradients
            optimizer.zero_grad()
            
            # Forward + backward + optimize
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            
            running_loss += loss.item()
            
            if i % 10 == 9:  # Print every 10 mini-batches
                print(f"Epoch {epoch+1}, Batch {i+1}: Loss = {running_loss/10:.4f}")
                running_loss = 0.0
        
        epoch_time = time.time() - start_time
        print(f"Epoch {epoch+1} completed in {epoch_time:.2f} seconds")
    
    print("\n=== Training completed ===")
    print(f"Total epochs: {args.epochs}")
    print(f"Final batch size: {args.batch_size}")
    print(f"Model: {model_name}")

if __name__ == "__main__":
    main()
EOF

echo "Created training script: $TRAIN_SCRIPT"

# Create a configuration file for submitting jobs
CONFIG_FILE="pytorch-jobs.json"

cat > "$CONFIG_FILE" << EOF
{
  "jobs": [
    {
      "jobDefinition": "$JOB_DEF_ARN",
      "jobQueue": "$GPU_JOB_QUEUE",
      "jobName": "pytorch-training-resnet50",
      "containerOverrides": {
        "environment": [
          {"name": "MODEL", "value": "resnet50"},
          {"name": "DATASET", "value": "imagenet"}
        ],
        "command": ["python", "train.py", "--epochs", "5", "--batch-size", "32"]
      }
    },
    {
      "jobDefinition": "$JOB_DEF_ARN",
      "jobQueue": "$GPU_JOB_QUEUE",
      "jobName": "pytorch-training-resnet18",
      "containerOverrides": {
        "environment": [
          {"name": "MODEL", "value": "resnet18"},
          {"name": "DATASET", "value": "cifar10"}
        ],
        "command": ["python", "train.py", "--epochs", "10", "--batch-size", "64"]
      }
    }
  ]
}
EOF

echo "Created job configuration file: $CONFIG_FILE"

echo -e "\n=== Job Definition and Configuration Created ==="
echo "To submit jobs using this configuration, run:"
echo "./submit-jobs.sh --config $CONFIG_FILE --monitor"

# Clean up temporary files
# rm -f "$JOB_DEF_FILE"
# Note: We're keeping the files for reference
