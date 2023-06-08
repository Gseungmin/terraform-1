resource "aws_vpc" "korea_main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "KoreaVPC"
  }
}

resource "aws_subnet" "korea_private_subnet" {
  vpc_id     = aws_vpc.korea_main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "KoreaPrivateSubnet"
  }
}

resource "aws_subnet" "korea_private_subnet_2" {
  vpc_id     = aws_vpc.korea_main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "KoreaPrivateSubnet2"
  }
}

resource "aws_subnet" "korea_public_subnet" {
  vpc_id     = aws_vpc.korea_main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-northeast-2a"

  map_public_ip_on_launch = true

  tags = {
    Name = "KoreaPublicSubnet"
  }
}

resource "aws_subnet" "korea_public_subnet_2" {
  vpc_id     = aws_vpc.korea_main.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "ap-northeast-2c"

  map_public_ip_on_launch = true

  tags = {
    Name = "KoreaPublicSubnet2"
  }
}

resource "aws_internet_gateway" "korea_igw" {
  vpc_id = aws_vpc.korea_main.id

  tags = {
    Name = "KoreaIGW"
  }
}

resource "aws_route_table" "korea_public_routetable" {
  vpc_id = aws_vpc.korea_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.korea_igw.id
  }

  tags = {
    Name = "KoreaPublicRouteTable"
  }
}

resource "aws_route_table_association" "korea_public_route_association" {
  subnet_id      = aws_subnet.korea_public_subnet.id
  route_table_id = aws_route_table.korea_public_routetable.id
}

resource "aws_route_table_association" "korea_public_route_association_2" {
  subnet_id      = aws_subnet.korea_public_subnet_2.id
  route_table_id = aws_route_table.korea_public_routetable.id
}

resource "aws_security_group" "korea_sg" {
  name        = "allow_all_korea"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.korea_main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "KoreaSecurity"
  }
}

resource "aws_security_group" "korea_rds_sg" {
  name        = "rds_sg"
  description = "Allow inbound traffic from EC2"
  vpc_id      = aws_vpc.korea_main.id
}

resource "aws_security_group_rule" "allow_ec2_to_rds" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = aws_security_group.korea_rds_sg.id
  source_security_group_id = aws_security_group.korea_sg.id
}

resource "aws_db_instance" "korea_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  identifier           = "def"
  username             = "ji"
  password             = "12345678"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  availability_zone    = "ap-northeast-2a"
  vpc_security_group_ids = [aws_security_group.korea_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.korea_private_subnet_group.name
}

resource "aws_db_subnet_group" "korea_private_subnet_group" {
  name       = "defaultdbgroup"
  subnet_ids = [aws_subnet.korea_private_subnet.id, aws_subnet.korea_private_subnet_2.id]

  tags = {
    Name = "Private DB subnet group"
  }
}

resource "aws_lb" "korea_alb" {
  name               = "korea-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.korea_sg.id]
  subnets            = [aws_subnet.korea_public_subnet.id, aws_subnet.korea_public_subnet_2.id]
}

resource "aws_lb_target_group" "korea_tg" {
  name     = "alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.korea_main.id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 15
    path                = "/"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "korea_server" {
  load_balancer_arn = aws_lb.korea_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.korea_tg.arn
  }
}

resource "aws_lb_listener_rule" "korea_rule" {
  listener_arn = aws_lb_listener.korea_server.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.korea_tg.arn
  }

  condition {
    path_pattern {
      values = ["/cloudclub/**"]
    }
  }
}

resource "aws_eip" "korea_public_instance_eip" {
  domain = "vpc"

  tags = {
    Name = "KoreaPublicIP"
  }
}

resource "aws_key_pair" "korea_pk" {
  key_name   = "korea_deployer_key"
  public_key = file("~/.ssh/id_rsa.pub")
}


resource "aws_launch_configuration" "korea_instance" {
  name          = "autoscailing-ec2"
  image_id      = "ami-0c9c942bd7bf113a2"
  key_name      = aws_key_pair.korea_pk.key_name
  instance_type = "t2.micro"
  
  security_groups = [aws_security_group.korea_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "korea_asg" {
  launch_configuration = aws_launch_configuration.korea_instance.id
  min_size             = 3
  max_size             = 5
  desired_capacity     = 3
  vpc_zone_identifier  = [aws_subnet.korea_public_subnet.id, aws_subnet.korea_public_subnet_2.id]

  tag {
    key                 = "korea"
    value               = "korea-as"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.korea_asg.id
  lb_target_group_arn   = aws_lb_target_group.korea_tg.arn
}

resource "aws_wafv2_web_acl" "korea_waf" {
  name        = "korea-wafacl"
  description = "a managed rule"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "korea-waf-rule"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "korea-waf-rule"
      sampled_requests_enabled   = false
    }
 }

  visibility_config {
    cloudwatch_metrics_enabled = false
    sampled_requests_enabled   = false
    metric_name                = "testACL"
  }
}

 resource "aws_wafv2_web_acl_association" "korea_waf_association" {
  resource_arn = aws_lb.korea_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.korea_waf.arn
}
