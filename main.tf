provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "production"
}

resource "aws_vpc" "main_network" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "main-vpc-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_network.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "public-subnet-${var.environment}"
  }
}

resource "aws_s3_bucket" "app_storage" {
  bucket        = "app-secure-storage-${var.environment}-data"
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.app_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.app_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_read_write_doc" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.app_storage.arn,
      "${aws_s3_bucket.app_storage.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_app_policy" {
  name        = "app-s3-rw-policy-${var.environment}"
  description = "Scoped access policy for application S3 operations"
  policy      = data.aws_iam_policy_document.s3_read_write_doc.json
}

data "aws_iam_policy_document" "ec2_trust_doc" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_compute_role" {
  name               = "app-compute-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_doc.json
}

resource "aws_iam_role_policy_attachment" "app_attach_s3" {
  role       = aws_iam_role.app_compute_role.name
  policy_arn = aws_iam_policy.s3_app_policy.arn
}
