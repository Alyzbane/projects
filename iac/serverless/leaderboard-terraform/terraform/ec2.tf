# Generate a fresh SSH key pair so `scripts/setup-www.sh` can push the
# frontend files without you having to already own an EC2 key pair.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/../${var.project_name}-key.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0600"
}

resource "aws_security_group" "dashboard" {
  name        = "${var.project_name}-dashboard-sg"
  description = "Allow HTTP (dashboard) and SSH (frontend deploy) to the leaderboard dashboard"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP"
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

  tags = local.tags
}

# EC2 + Nginx dashboard host. user_data only installs/starts nginx -
# the actual www files are pushed afterwards by scripts/setup-www.sh
# once the API Gateway invoke URL is known.
resource "aws_instance" "dashboard" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.dashboard.id]

  user_data = file("${path.module}/templates/user_data.sh")

  tags = merge(local.tags, {
    Name = "${var.project_name}-dashboard"
  })
}
