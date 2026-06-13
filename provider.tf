# AWSプロバイダーの設定
provider "aws" {
  region = "ap-northeast-1" # 東京リージョン
}
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}