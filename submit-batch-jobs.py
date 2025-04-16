#!/usr/bin/env python3
"""
AWS Batch Job Submission Script

This script allows for submitting jobs to AWS Batch with support for different job definitions,
job queues, and parameters. It can submit single jobs or multiple jobs in batch.

Usage:
    python submit-batch-jobs.py --job-definition <job-def> --job-queue <queue> [options]
    python submit-batch-jobs.py --config <config-file.json> [options]

Examples:
    # Submit a single job
    python submit-batch-jobs.py --job-definition gpu-image-processing-benchmark \
                               --job-queue gpu-job-queue \
                               --job-name my-gpu-job

    # Submit a job with environment variables
    python submit-batch-jobs.py --job-definition gpu-image-processing-benchmark \
                               --job-queue gpu-job-queue \
                               --env "MODEL_TYPE=resnet,BATCH_SIZE=32"

    # Submit multiple jobs from a config file
    python submit-batch-jobs.py --config batch-jobs.json
"""

import argparse
import boto3
import json
import sys
import time
import os
from datetime import datetime
from typing import Dict, List, Optional, Union, Any


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Submit jobs to AWS Batch')
    
    # Job definition and queue options
    parser.add_argument('--job-definition', type=str, help='Job definition name or ARN')
    parser.add_argument('--job-queue', type=str, help='Job queue name or ARN')
    parser.add_argument('--job-name', type=str, help='Name for the job')
    
    # Configuration file option
    parser.add_argument('--config', type=str, help='Path to JSON configuration file for batch job submission')
    
    # Job parameters
    parser.add_argument('--command', type=str, help='Command override for the job')
    parser.add_argument('--env', type=str, help='Environment variables in format "KEY1=value1,KEY2=value2"')
    parser.add_argument('--memory', type=int, help='Memory override in MB')
    parser.add_argument('--vcpus', type=int, help='vCPUs override')
    parser.add_argument('--gpu', type=int, help='Number of GPUs to use')
    parser.add_argument('--timeout', type=int, help='Timeout in seconds')
    
    # Batch options
    parser.add_argument('--count', type=int, default=1, help='Number of identical jobs to submit')
    parser.add_argument('--depends-on', type=str, help='Job IDs this job depends on, comma separated')
    parser.add_argument('--array-size', type=int, help='Size of the job array')
    
    # Output options
    parser.add_argument('--output', type=str, help='Output file for job IDs')
    parser.add_argument('--monitor', action='store_true', help='Monitor job status after submission')
    parser.add_argument('--region', type=str, help='AWS region')
    parser.add_argument('--profile', type=str, help='AWS profile name')
    
    return parser.parse_args()


def parse_env_vars(env_string: str) -> Dict[str, str]:
    """Parse environment variables from a string format KEY1=value1,KEY2=value2."""
    if not env_string:
        return {}
    
    env_vars = {}
    for pair in env_string.split(','):
        if '=' in pair:
            key, value = pair.split('=', 1)
            env_vars[key.strip()] = value.strip()
    
    return env_vars


def load_config(config_path: str) -> Dict[str, Any]:
    """Load job configuration from a JSON file."""
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"Error loading config file: {e}")
        sys.exit(1)


def get_job_parameters(args) -> Dict[str, Any]:
    """Build job parameters from command line arguments."""
    params = {
        'jobDefinition': args.job_definition,
        'jobQueue': args.job_queue,
        'jobName': args.job_name or f"batch-job-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    }
    
    # Optional parameters
    container_overrides = {}
    
    if args.command:
        container_overrides['command'] = args.command.split()
    
    if args.env:
        env_vars = parse_env_vars(args.env)
        if env_vars:
            container_overrides['environment'] = [{'name': k, 'value': v} for k, v in env_vars.items()]
    
    if args.memory:
        container_overrides['memory'] = args.memory
    
    if args.vcpus:
        container_overrides['vcpus'] = args.vcpus
    
    if args.gpu:
        container_overrides['resourceRequirements'] = [{'type': 'GPU', 'value': str(args.gpu)}]
    
    if container_overrides:
        params['containerOverrides'] = container_overrides
    
    if args.timeout:
        params['timeout'] = {'attemptDurationSeconds': args.timeout}
    
    if args.depends_on:
        job_ids = [job_id.strip() for job_id in args.depends_on.split(',')]
        params['dependsOn'] = [{'jobId': job_id, 'type': 'SEQUENTIAL'} for job_id in job_ids]
    
    if args.array_size:
        params['arrayProperties'] = {'size': args.array_size}
    
    return params


def submit_job(batch_client, job_params: Dict[str, Any]) -> str:
    """Submit a job to AWS Batch and return the job ID."""
    try:
        response = batch_client.submit_job(**job_params)
        return response['jobId']
    except Exception as e:
        print(f"Error submitting job: {e}")
        return None


def monitor_jobs(batch_client, job_ids: List[str], interval: int = 30) -> None:
    """Monitor the status of submitted jobs."""
    print(f"Monitoring {len(job_ids)} jobs...")
    
    jobs_to_monitor = job_ids.copy()
    completed_jobs = set()
    
    try:
        while jobs_to_monitor:
            response = batch_client.describe_jobs(jobs=jobs_to_monitor)
            
            print("\n" + "=" * 80)
            print(f"Job Status Update: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print("=" * 80)
            
            for job in response['jobs']:
                job_id = job['jobId']
                job_name = job['jobName']
                status = job['status']
                
                # Print status with color based on status
                status_display = status
                if status == 'SUCCEEDED':
                    status_display = f"\033[92m{status}\033[0m"  # Green
                elif status == 'FAILED':
                    status_display = f"\033[91m{status}\033[0m"  # Red
                elif status in ['RUNNING', 'STARTING']:
                    status_display = f"\033[94m{status}\033[0m"  # Blue
                elif status == 'SUBMITTED':
                    status_display = f"\033[93m{status}\033[0m"  # Yellow
                
                print(f"Job: {job_name} (ID: {job_id}) - Status: {status_display}")
                
                # If job is in a terminal state, add to completed jobs
                if status in ['SUCCEEDED', 'FAILED']:
                    completed_jobs.add(job_id)
            
            # Remove completed jobs from monitoring list
            jobs_to_monitor = [job_id for job_id in jobs_to_monitor if job_id not in completed_jobs]
            
            if jobs_to_monitor:
                print(f"\nWaiting {interval} seconds for next update...")
                time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\nMonitoring stopped by user.")


def main():
    """Main function to parse arguments and submit jobs."""
    args = parse_args()
    
    # Set up AWS client
    session_kwargs = {}
    if args.region:
        session_kwargs['region_name'] = args.region
    if args.profile:
        session_kwargs['profile_name'] = args.profile
    
    session = boto3.Session(**session_kwargs)
    batch_client = session.client('batch')
    
    submitted_job_ids = []
    
    # Process based on config file or command line arguments
    if args.config:
        config = load_config(args.config)
        
        if 'jobs' in config:
            # Multiple jobs defined in config
            for job_config in config['jobs']:
                job_params = job_config
                
                # Submit the job
                print(f"Submitting job: {job_params.get('jobName', 'unnamed')}")
                job_id = submit_job(batch_client, job_params)
                
                if job_id:
                    submitted_job_ids.append(job_id)
                    print(f"Job submitted with ID: {job_id}")
        else:
            # Single job defined in config
            job_params = config
            
            # Submit the job
            print(f"Submitting job: {job_params.get('jobName', 'unnamed')}")
            job_id = submit_job(batch_client, job_params)
            
            if job_id:
                submitted_job_ids.append(job_id)
                print(f"Job submitted with ID: {job_id}")
    
    else:
        # Process command line arguments
        if not args.job_definition or not args.job_queue:
            print("Error: --job-definition and --job-queue are required when not using --config")
            sys.exit(1)
        
        job_params = get_job_parameters(args)
        
        # Submit multiple identical jobs if requested
        for i in range(args.count):
            if args.count > 1:
                # Append index to job name for multiple jobs
                job_params['jobName'] = f"{job_params['jobName']}-{i+1}"
            
            print(f"Submitting job: {job_params['jobName']}")
            job_id = submit_job(batch_client, job_params)
            
            if job_id:
                submitted_job_ids.append(job_id)
                print(f"Job submitted with ID: {job_id}")
    
    # Write job IDs to output file if requested
    if args.output and submitted_job_ids:
        with open(args.output, 'w') as f:
            for job_id in submitted_job_ids:
                f.write(f"{job_id}\n")
        print(f"Job IDs written to {args.output}")
    
    # Monitor jobs if requested
    if args.monitor and submitted_job_ids:
        monitor_jobs(batch_client, submitted_job_ids)
    
    print(f"Total jobs submitted: {len(submitted_job_ids)}")


if __name__ == "__main__":
    main()
