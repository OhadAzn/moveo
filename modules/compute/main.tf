data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
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
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash
              set -e
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              
              echo '<h1>Hello from Terraform!</h1><p>Traffic: Client → ALB → EC2 → Docker → Nginx</p>' > /tmp/index.html
              
              docker run -d -p 80:80 --name nginx --restart always nginx:alpine
              sleep 5
              docker cp /tmp/index.html nginx:/usr/share/nginx/html/index.html
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
