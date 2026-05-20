# ─────────────────────────────────────────────────────────────
# Module: Bastion Host
#
# A small EC2 instance in a public subnet that lets you SSH tunnel
# into RDS from your laptop:
#
#   ssh -L 5432:<rds-endpoint>:5432 ec2-user@<bastion-ip> -i ~/.ssh/<key>.pem
#   psql -h localhost -U shopnow -d shopnow
# ─────────────────────────────────────────────────────────────

# Latest Amazon Linux 2023
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.project}-bastion-sg"
  description = "Bastion host: SSH from allowed CIDR only"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-bastion-sg" })
}

# Allow bastion to reach RDS
resource "aws_security_group_rule" "bastion_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.rds_sg_id
  source_security_group_id = aws_security_group.bastion.id
  description              = "Bastion to RDS"
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(var.tags, { Name = "${var.project}-bastion" })
}
