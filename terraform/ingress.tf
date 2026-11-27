# the hosted zone already exists (created once, outside Terraform)
data "aws_route53_zone" "this" {
  name = var.domain
}

# --- AWS Load Balancer Controller: turns an Ingress into an ALB ---

module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${var.project}-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.7.0"
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    # pods can't read region/VPC from the node (IMDS hop limit 1), so pass them in
    region         = var.region
    vpcId          = module.vpc.vpc_id
    serviceAccount = { name = "aws-load-balancer-controller" }
  })]

  depends_on = [module.eks, module.lb_controller_pod_identity]
}

# --- ExternalDNS: creates shop.<domain> in Route 53, pointing at the ALB ---

module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                          = "${var.project}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.this.arn] # this zone only

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.24.0"
  namespace  = "kube-system"

  values = [yamlencode({
    provider       = { name = "aws" }
    sources        = ["ingress"]
    domainFilters  = [var.domain]
    policy         = "sync"      # deletes the record when the Ingress is deleted
    txtOwnerId     = var.project # only touches records it created
    serviceAccount = { name = "external-dns" }
    env            = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
  })]

  depends_on = [module.eks, module.external_dns_pod_identity]
}