module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Network comes from the VPC state, never hard-coded. See data.tf.
  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnets

  # Worker nodes sit in private subnets; only the API endpoint is public,
  # which is what lets kubectl reach the cluster from a workstation.
  endpoint_public_access  = var.endpoint_public_access
  endpoint_private_access = true

  # Give the IAM identity that runs terraform apply admin rights on the
  # cluster, otherwise kubectl returns "You must be logged in to the server".
  enable_cluster_creator_admin_permissions = true

  enable_irsa = true

  # Without these the cluster comes up with an empty kube-system: no CNI, so
  # every node stays NotReady and the node groups never finish creating.
  # The module does not bootstrap them on its own - they must be declared.
  addons = {
    vpc-cni = {
      before_compute = true # the network plugin has to exist before nodes join
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    # Single general-purpose pool for every namespace in this project
    # (staging, production, mlops-system, monitoring). No GPU pool this time -
    # the final project's model is a lightweight sklearn classifier.
    cpu-nodes = {
      instance_types = var.cpu_node_group.instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.cpu_node_group.min_size
      max_size     = var.cpu_node_group.max_size
      desired_size = var.cpu_node_group.desired_size

      labels = {
        workload = "cpu"
      }

      tags = {
        NodeGroup = "cpu-nodes"
      }
    }
  }

  tags = {
    Name = var.cluster_name
  }
}
