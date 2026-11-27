module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.project
  kubernetes_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes live in the private subnets

  # kubectl from my laptop only
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  # whoever runs terraform apply becomes cluster admin
  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    # EBS disks for Kafka + Mongo - gets its AWS permissions through Pod Identity, no keys
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  # 4 x 8 GB nodes spread over the 3 private subnets (~24 GB needed + headroom)
  eks_managed_node_groups = {
    main = {
      name           = "${var.project}-node" # shows as the EC2 Name tag
      instance_types = [var.node_instance_type]
      # min_size       = 3
      # max_size       = 4
      # desired_size   = 3
      min_size     = 4
      max_size     = 5
      desired_size = 4
    }
  }
}

# IAM role the EBS driver uses to create and attach disks
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.project}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}