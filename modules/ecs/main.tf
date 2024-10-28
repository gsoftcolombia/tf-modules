module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.11.4"

  cluster_name = "${var.name_prefix}-cluster"

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/cluster"
      }
    }
  }
  cloudwatch_log_group_name              = "/aws/ecs/cluster"
  cloudwatch_log_group_retention_in_days = 7

  default_capacity_provider_use_fargate = false

  autoscaling_capacity_providers = {
    general_1 = {
      auto_scaling_group_arn = module.autoscaling_general_1.autoscaling_group_arn

      #managed_scaling = {
      #  maximum_scaling_step_size = 1
      #  minimum_scaling_step_size = 1
      #  status                    = "ENABLED"
      #  target_capacity           = 60
      #}

      default_capacity_provider_strategy = {
        weight = 20
        base   = 0
      }
    }
  }
}

module "autoscaling_general_1" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 8.0.0"

  name = "${var.name_prefix}-asg"

  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0
  health_check_type         = "EC2"
  vpc_zone_identifier       = var.vpc_subnet_ids

  # Launch template
  launch_template_name        = "${var.name_prefix}-asg-lt"
  launch_template_description = "${var.name_prefix}-asg Launch template"
  update_default_version      = true

  image_id          = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  key_name          = var.key_pair_name
  instance_type     = "t3a.micro"
  ebs_optimized     = true
  enable_monitoring = true

  create_iam_instance_profile = true
  iam_role_name               = "${var.name_prefix}-asg"
  iam_role_description        = "ECS role for ${var.name_prefix}-asg"

  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  user_data                       = base64encode(var.node_user_data)
  ignore_desired_capacity_changes = true

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # This will ensure imdsv2 is enabled, required, and a single hop which is aws security
  # best practices
  # See https://docs.aws.amazon.com/securityhub/latest/userguide/autoscaling-controls.html#autoscaling-4
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  security_groups = [module.autoscaling_sg.security_group_id]

}

module "autoscaling_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.2.0"

  name         = "${var.name_prefix}-sg"
  description  = "${var.name_prefix} Security Group"
  vpc_id       = var.vpc_id
  egress_rules = ["all-all"]
}

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}