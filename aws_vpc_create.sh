#!/bin/bash

#########################
#Description: This script creates a VPC in AWS using the AWS CLI.
#Author: Your Name
# - Create VPC
# - Create a public subnet
#
# - Verify if user has AWS installed and configured, user might be using windows, linux or macos

# Variables

VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.0.0/24"
REGION="us-east-1"
VPC_NAME="MyVPC"
SUBNET_NAME="MySubnet"
SUBNET_AZ="us-east-1a"

if ! command -v aws &> /dev/null
then
    echo "AWS CLI could not be found. Please install and configure AWS CLI before running this script."
    exit
fi

# Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $REGION --query 'Vpc.VpcId' --output text)
echo "VPC created with ID: $VPC_ID"

#Add Name tag to VPC
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION
echo "Added Name tag to VPC: $VPC_NAME"

#Create Subnet
echo "Creating Subnet..."
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR --availability-zone $SUBNET_AZ --region $REGION --query 'Subnet.SubnetId' --output text)
echo "Subnet created with ID: $SUBNET_ID"

#Add Name tag to Subnet
aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value=$SUBNET_NAME --region $REGION
echo "Added Name tag to Subnet: $SUBNET_NAME"