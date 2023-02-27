# Create a security group
resource "aws_security_group" "web" {
  name_prefix = "web-"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "web" {
  ami                         = "ami-0dfcb1ef8550277af"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
  user_data                   = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install httpd -y
              echo "<html><head><title>Hello world</title></head><body><h1>Hello world</h1></body></html>" | sudo tee /var/www/html/index.html
              sudo systemctl enable httpd
              sudo systemctl start httpd
              EOF
}

# Create an elastic IP address
resource "aws_eip" "web" {
  vpc = true
}

# Associate the elastic IP address with the instance
resource "aws_eip_association" "web" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.web.id
}

resource "aws_default_subnet" "default1" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default2" {
  availability_zone = "us-east-1b"
}
# Create a load balancer
resource "aws_lb" "web" {
  name                   = "web-lb-tf"
  internal               = false
  load_balancer_type     = "application"
  security_groups = [aws_security_group.web.id]
  subnets                = [aws_default_subnet.default1.id,aws_default_subnet.default2.id ]



  tags = {
    Name = "web"
  }
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "web_https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"

  #ssl_policy      = "ELBSecurityPolicy-TLS-1-2-2017-01"
  #certificate_arn = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

data "aws_vpc" "vpc" {
  id = "vpc-0149962fc3ae25201"
}
resource "aws_lb_target_group" "web" {
  name        = "web"
  port        = 443
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.vpc.id
  target_type = "instance"

  health_check {
    path = "/"
  }

  tags = {
    Name = "web"
  }
}

resource "aws_lb_target_group_attachment" "example" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 443
}

resource "aws_launch_configuration" "example" {
  name_prefix            = "example-lc-"
  image_id               = "ami-0dfcb1ef8550277af"
  instance_type          = "t2.micro"
  security_groups = [aws_security_group.web.id]
  user_data              = <<-EOF
              #!/bin/bash
              echo "Hello, World!" > index.html
              nohup python -m SimpleHTTPServer 80 &
              EOF
}

resource "aws_autoscaling_group" "example" {
  name_prefix          = "example-asg-"
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.example.id
  max_size             = 3
  min_size             = 1
  target_group_arns    = [aws_lb_target_group.web.arn]
  vpc_zone_identifier  = [aws_default_subnet.default1.id,aws_default_subnet.default2.id]
  tag {
    key                 = "Name"
    value               = "example-autoscaling-group"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
