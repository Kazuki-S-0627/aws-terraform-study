# VPCの定義
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "bastion-demo-vpc"
  }
}
# パブリックサブネット
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true # ここに立てたEC2には自動でパブリックIPを付与する

  tags = {
    Name = "public-subnet"
  }
}
# プライベートサブネット
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "private-subnet"
  }
}
# インターネットゲートウェイ
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "bastion-igw"
  }
}
# パブリックサブネット用のルートテーブル（地図）
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-rt"
  }
}

# インターネットへの道案内（ルート）
resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# パブリックサブネットに地図を配る（関連付け）
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# ==========================================
# 1. NATゲートウェイとプライベートルート
# ==========================================
# NATゲートウェイ用の固定IP（Elastic IP）
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "bastion-nat-eip" }
}

# NATゲートウェイ（パブリックサブネットに配置）
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "bastion-nat" }
}

# プライベートサブネット用のルートテーブル
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rt" }
}

# プライベートからNATへの道案内
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# プライベートサブネットに地図を配る
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


# ==========================================
# 2. セキュリティグループ（ファイアウォール）
# ==========================================
# 踏み台サーバー用（外部からのSSHを許可）
resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ※本来は自分のPCのIPに絞るのが安全です
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bastion-sg" }
}

# Webサーバー用（踏み台からのSSHと、Webアクセスを許可）
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow SSH from Bastion and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id] # 踏み台からのみ許可
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "web-sg" }
}


# ==========================================
# 3. EC2インスタンス
# ==========================================
# 最新のAmazon Linux 2023のAMIを自動取得する設定
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 踏み台サーバー (Bastion EC2)
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  
  key_name = "bastion-key" # ※手動で作ったキーペア（.pem）の名前をここに入力してください（拡張子不要）

  tags = { Name = "bastion-ec2" }
}

# Webサーバー (Private EC2)
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.web.id]

  key_name = "bastion-key" # ※踏み台と同じキーペア名を指定

  # 【魔法の設定】起動時に自動でNginxをインストールするスクリプト
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = { Name = "web-server" }
}