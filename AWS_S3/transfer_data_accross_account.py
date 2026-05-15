import json
import boto3
import subprocess
import os
import sys
import time
from decouple import config

def get_iam_client(access_key, secret_key):
    return boto3.client(
        'iam',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key
    )

def get_s3_client(access_key, secret_key):
    return boto3.client(
        's3',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key
    )

def create_destination_bucket_if_not_exists(s3_client, bucket_name):
    print(f"Checking if destination bucket '{bucket_name}' exists...")
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        print("Bucket already exists. Skipping creation.")
    except s3_client.exceptions.ClientError as e:
        error_code = e.response.get('Error', {}).get('Code')
        if error_code == '404' or error_code == 'NoSuchBucket':
            print("Bucket does not exist. Creating...")
            region = s3_client.meta.region_name
            if region and region != 'us-east-1':
                s3_client.create_bucket(
                    Bucket=bucket_name,
                    CreateBucketConfiguration={'LocationConstraint': region}
                )
            else:
                s3_client.create_bucket(Bucket=bucket_name)
            print("Bucket created successfully.")
        else:
            print(f"Error checking bucket: {e}")
            raise
    
    print(f"Turning off 'Block all public access' for bucket '{bucket_name}'...")
    s3_client.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            'BlockPublicAcls': False,
            'IgnorePublicAcls': False,
            'BlockPublicPolicy': False,
            'RestrictPublicBuckets': False
        }
    )
    print("'Block all public access' turned off successfully.")

def setup_destination_user_and_policy(iam_client, account_id, bucket_name, policy_name, user_name):
    print(f"Checking if policy '{policy_name}' exists...")
    policy_arn = f"arn:aws:iam::{account_id}:policy/{policy_name}"
    
    try:
        iam_client.get_policy(PolicyArn=policy_arn)
        print("Policy already exists. Skipping creation.")
    except iam_client.exceptions.NoSuchEntityException:
        print("Policy does not exist. Creating...")
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:*"
                    ],
                    "Resource": [
                        f"arn:aws:s3:::{bucket_name}",
                        f"arn:aws:s3:::{bucket_name}/*"
                    ]
                }
            ]
        }
        response = iam_client.create_policy(
            PolicyName=policy_name,
            PolicyDocument=json.dumps(policy_document)
        )
        policy_arn = response['Policy']['Arn']
        print(f"Policy created successfully with ARN: {policy_arn}")

    print(f"Checking if user '{user_name}' exists...")
    try:
        iam_client.get_user(UserName=user_name)
        print("User already exists. Skipping creation.")
    except iam_client.exceptions.NoSuchEntityException:
        print("User does not exist. Creating...")
        iam_client.create_user(UserName=user_name)
        print("User created successfully.")
    
    print(f"Attaching policy '{policy_arn}' to user '{user_name}'...")
    try:
        iam_client.attach_user_policy(
            UserName=user_name,
            PolicyArn=policy_arn
        )
        print("Policy attached successfully.")
    except Exception as e:
        print(f"Failed to attach policy or it's already attached: {e}")

def configure_destination_bucket(s3_client, account_id, bucket_name, user_name):
    print(f"Editing destination bucket policy for '{bucket_name}'...")
    bucket_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadAccess",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": f"arn:aws:s3:::{bucket_name}/*"
            },
            {
                "Sid": "AllowIAMUserUpload",
                "Effect": "Allow",
                "Principal": {
                    "AWS": f"arn:aws:iam::{account_id}:user/{user_name}"
                },
                "Action": [
                    "s3:PutObject",
                    "s3:PutObjectAcl"
                ],
                "Resource": f"arn:aws:s3:::{bucket_name}/*"
            }
        ]
    }
    
    max_retries = 6
    for attempt in range(max_retries):
        try:
            s3_client.put_bucket_policy(
                Bucket=bucket_name,
                Policy=json.dumps(bucket_policy)
            )
            print("Destination bucket policy updated successfully.")
            break
        except s3_client.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'MalformedPolicy' and attempt < max_retries - 1:
                print(f"Policy rejected (likely IAM propagation delay). Retrying in 10 seconds... ({attempt+1}/{max_retries})")
                time.sleep(10)
            else:
                raise

    print(f"Setting CORS for destination bucket '{bucket_name}'...")
    cors_configuration = {
        'CORSRules': [
            {
                'AllowedHeaders': ['*'],
                'AllowedMethods': ['PUT', 'POST', 'DELETE'],
                'AllowedOrigins': ['*'],
                'ExposeHeaders': []
            },
            {
                'AllowedHeaders': ['*'],
                'AllowedMethods': ['GET'],
                'AllowedOrigins': ['*'],
                'ExposeHeaders': []
            }
        ]
    }
    s3_client.put_bucket_cors(
        Bucket=bucket_name,
        CORSConfiguration=cors_configuration
    )
    print("CORS updated successfully.")

def configure_source_bucket(s3_client, source_bucket, dest_account_id):
    print(f"Configuring source bucket '{source_bucket}' to allow cross-account read for account '{dest_account_id}'...")
    
    try:
        response = s3_client.get_bucket_policy(Bucket=source_bucket)
        policy = json.loads(response['Policy'])
    except s3_client.exceptions.ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchBucketPolicy':
            policy = {
                "Version": "2012-10-17",
                "Statement": []
            }
        else:
            print(f"Error fetching source bucket policy: {e}")
            raise

    cross_account_stmt = {
        "Sid": "AllowCrossAccountRead",
        "Effect": "Allow",
        "Principal": {
            "AWS": f"arn:aws:iam::{dest_account_id}:root"
        },
        "Action": [
            "s3:ListBucket",
            "s3:GetObject"
        ],
        "Resource": [
            f"arn:aws:s3:::{source_bucket}",
            f"arn:aws:s3:::{source_bucket}/*"
        ]
    }

    statements = policy.get("Statement", [])
    has_stmt = False
    for stmt in statements:
        if stmt.get("Sid") == "AllowCrossAccountRead":
            has_stmt = True
            break
            
    if not has_stmt:
        statements.append(cross_account_stmt)
        policy["Statement"] = statements
        s3_client.put_bucket_policy(
            Bucket=source_bucket,
            Policy=json.dumps(policy)
        )
        print("Source bucket policy updated for cross-account read.")
    else:
        print("Source bucket already has cross-account read policy.")

def run_sync_command(source_bucket, dest_bucket, dest_access_key, dest_secret_key):
    print(f"\nStarting fast sync from '{source_bucket}' to '{dest_bucket}'...")
    
    env = os.environ.copy()
    env['AWS_ACCESS_KEY_ID'] = dest_access_key
    env['AWS_SECRET_ACCESS_KEY'] = dest_secret_key
    
    cmd = [
        "aws", "s3", "sync",
        f"s3://{source_bucket}",
        f"s3://{dest_bucket}",
        "--acl", "bucket-owner-full-control",
        "--copy-props", "none"
    ]
    
    print(f"Running command: {' '.join(cmd)}")
    
    process = subprocess.Popen(
        cmd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True
    )
    
    for line in process.stdout:
        print(line, end='')
        
    process.wait()
    if process.returncode == 0:
        print("Sync completed successfully.")
    else:
        print(f"Sync failed with return code {process.returncode}")

def main():
    src_bucket = config('SOURCE_BUCKET_NAME')
    dest_bucket = config('DESTINATION_BUCKET_NAME')
    dest_account_id = config('DESTINATION_ACCOUNT_ID')
    dest_access_key = config('DESTINATION_ACCESS_KEY_ID')
    dest_secret_key = config('DESTINATION_SECRET_ACCESS_KEY')
    
    src_access_key = config('SOURCE_ACCESS_KEY_ID')
    src_secret_key = config('SOURCE_SECRET_ACCESS_KEY')
    
    new_user_name = config('NEW_USER_NAME')
    new_policy_name = config('NEW_USER_POLICY_NAME')
    
    # Initialize AWS clients
    dest_iam_client = get_iam_client(dest_access_key, dest_secret_key)
    dest_s3_client = get_s3_client(dest_access_key, dest_secret_key)
    src_s3_client = get_s3_client(src_access_key, src_secret_key)
    
    print("--- 1 & 2: Setting up Destination User and Policy ---")
    setup_destination_user_and_policy(
        dest_iam_client, 
        dest_account_id, 
        dest_bucket, 
        new_policy_name, 
        new_user_name
    )
    
    print("\n--- 3: Creating Destination Bucket (If Not Exists) ---")
    create_destination_bucket_if_not_exists(
        dest_s3_client, 
        dest_bucket
    )
    
    print("\n--- 4 & 5: Configuring Destination Bucket ---")
    configure_destination_bucket(
        dest_s3_client, 
        dest_account_id, 
        dest_bucket, 
        new_user_name
    )
    
    print("\n--- Configuring Source Bucket for Cross-Account Read ---")
    # This step is critical to allow the destination account to read the source bucket
    configure_source_bucket(
        src_s3_client,
        src_bucket,
        dest_account_id
    )
    
    print("\n--- 6: Running Data Sync Command ---")
    run_sync_command(
        src_bucket,
        dest_bucket,
        dest_access_key,
        dest_secret_key
    )

if __name__ == "__main__":
    main()
