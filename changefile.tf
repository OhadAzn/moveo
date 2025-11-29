data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_role" "ssm" {
  name_prefix = "${var.name}-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-ssm-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name_prefix = "${var.name}-ssm-"
  role        = aws_iam_role.ssm.name

  tags = merge(var.tags, { Name = "${var.name}-ssm-profile" })
}

resource "aws_security_group" "ec2" {
  name_prefix = "${var.name}-ec2-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-sg" })
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  
  associate_public_ip_address = false
  
  depends_on = [
    aws_iam_role.ssm,
    aws_iam_role_policy_attachment.ssm,
    aws_iam_instance_profile.ssm
  ]
  user_data = <<-EOF
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

for i in $(seq 1 10); do
  apt-get update && break || {
    echo "apt update failed — sleeping 15s before retry #$i"
    sleep 15
  }
done

# --- update + prerequisites ---
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

# --- Setup Docker official repo ---
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list

DEBIAN_FRONTEND=noninteractive apt-get update -y

# --- Install Docker Engine ---
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true

# --- Start & enable Docker ---
systemctl enable --now docker || true

# --- Verify Docker works ---
docker --version || true
docker run --rm hello-world || true

docker run -d -p 80:80 --name nginx_app --restart always nginx:alpine || true

docker exec nginx_app sh -c "echo 'yo this is nginx' > /usr/share/nginx/html/index.html" || true

echo " ==== user-data finished ===="
EOF
  root_block_device {
    volume_size = 10
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = merge(var.tags, { Name = "${var.name}-web" })
}

resource "aws_lb_target_group_attachment" "web" {
  count            = var.alb_target_group_arn != "" ? 1 : 0
  target_group_arn = var.alb_target_group_arn
  target_id        = aws_instance.web.id
  port             = 80
}
