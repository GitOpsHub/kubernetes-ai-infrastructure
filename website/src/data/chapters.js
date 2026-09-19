export const CHAPTERS = [
  {
    id: '00-prerequisites',
    number: '00',
    title: 'Prerequisites & Cluster Setup',
    route: '/prerequisites',
    category: 'Foundations',
    categoryIcon: '🏗️',
    description: 'CLI tooling, AWS authentication, EKS v1.31 creation with Terraform/eksctl, and CPU test lab.',
  },
  {
    id: '01-gpu-nodes',
    number: '01',
    title: 'GPU Nodes & Scheduling',
    route: '/gpu-nodes',
    category: 'Foundations',
    categoryIcon: '🏗️',
    description: 'EC2 GPU instance families, GPU discovery daemonset, taints, tolerations, and nodeAffinity.',
  },
  {
    id: '02-gpu-operator',
    number: '02',
    title: 'NVIDIA GPU Operator',
    route: '/gpu-operator',
    category: 'Foundations',
    categoryIcon: '🏗️',
    description: 'Automated NVIDIA driver deployment, container toolkit, Device Plugin, and DCGM exporter.',
  },
  {
    id: '03-gpu-sharing',
    number: '03',
    title: 'GPU Sharing & DRA',
    route: '/gpu-sharing',
    category: 'Foundations',
    categoryIcon: '🏗️',
    description: 'Dynamic Resource Allocation (DRA), Multi-Instance GPU (MIG), and Time-Slicing strategies.',
  },
  {
    id: '04-gpu-observability',
    number: '04',
    title: 'GPU Observability',
    route: '/gpu-observability',
    category: 'Foundations',
    categoryIcon: '🏗️',
    description: 'Prometheus, DCGM metrics, Grafana dashboards, GPU temperature, power, and throttling alerts.',
  },
  {
    id: '05-model-storage',
    number: '05',
    title: 'Model Storage & Data',
    route: '/model-storage',
    category: 'Data & Batch',
    categoryIcon: '📦',
    description: 'High-throughput weights delivery, Amazon S3 CSI driver, Mountpoint, and persistent volume caching.',
  },
  {
    id: '06-batch-kueue',
    number: '06',
    title: 'Batch Jobs & Kueue',
    route: '/batch-kueue',
    category: 'Data & Batch',
    categoryIcon: '📦',
    description: 'Multi-tenant GPU job queueing, ClusterQueues, LocalQueues, fair-sharing, and preemption.',
  },
  {
    id: '07-distributed-training',
    number: '07',
    title: 'Distributed Training (Kubeflow Trainer)',
    route: '/distributed-training',
    category: 'Training',
    categoryIcon: '🧠',
    description: 'PyTorchJob, multi-node DDP/FSDP training, NCCL RDMA/EFA networking, and Kubeflow Training Operator v2.',
  },
  {
    id: '08-ray',
    number: '08',
    title: 'Ray on Kubernetes',
    route: '/ray',
    category: 'Training',
    categoryIcon: '🧠',
    description: 'KubeRay operator, RayClusters, RayJobs, elastic workers, and Ray Train integration.',
  },
  {
    id: '09-vllm-inference',
    number: '09',
    title: 'LLM Inference with vLLM',
    route: '/vllm-inference',
    category: 'Serving',
    categoryIcon: '🚀',
    description: 'High-performance LLM serving, PagedAttention, KV cache management, and continuous batching.',
  },
  {
    id: '10-autoscaling-inference',
    number: '10',
    title: 'Autoscaling Inference',
    route: '/autoscaling-inference',
    category: 'Serving',
    categoryIcon: '🚀',
    description: 'KEDA autoscaling based on vLLM Prometheus metrics (queue depth, latency) and HPA.',
  },
  {
    id: '11-kserve',
    number: '11',
    title: 'KServe',
    route: '/kserve',
    category: 'Serving',
    categoryIcon: '🚀',
    description: 'Cloud-native model serving with InferenceService, scale-to-zero, and canary traffic routing.',
  },
  {
    id: '12-inference-gateway',
    number: '12',
    title: 'Inference Gateway & Multinode Serving',
    route: '/inference-gateway',
    category: 'Serving',
    categoryIcon: '🚀',
    description: 'Kubernetes Gateway API, Envoy AI Gateway, tensor parallelism, and multi-node inference.',
  },
  {
    id: '13-node-autoscaling',
    number: '13',
    title: 'Node Autoscaling & Cost',
    route: '/node-autoscaling',
    category: 'Platform',
    categoryIcon: '⚙️',
    description: 'Karpenter GPU NodePools, Spot GPU consolidation, disruption budgets, and OpenCost telemetry.',
  },
  {
    id: '14-security',
    number: '14',
    title: 'Multi-tenancy & Security',
    route: '/security',
    category: 'Platform',
    categoryIcon: '⚙️',
    description: 'Namespaces, RBAC, NetworkPolicies, pod security admission, and IRSA/EKS Pod Identity for S3.',
  },
  {
    id: '15-gitops',
    number: '15',
    title: 'GitOps & MLOps Pipelines',
    route: '/gitops',
    category: 'Platform',
    categoryIcon: '⚙️',
    description: 'Argo CD declarative infrastructure, GitHub Actions CI/CD pipelines, and automated manifests sync.',
  },
  {
    id: '16-capstone',
    number: '16',
    title: 'Capstone AI Platform',
    route: '/capstone',
    category: 'Platform',
    categoryIcon: '⚙️',
    description: 'Production end-to-end AI platform combining Karpenter, Kueue, Ray, vLLM, and Grafana.',
  },
  {
    id: '17-day2-ops',
    number: '17',
    title: 'Platform Day-2 Operations',
    route: '/day2-ops',
    category: 'Operate',
    categoryIcon: '🔧',
    description: 'Cluster upgrades, driver rollouts, node drain safety, GPU health checks, and runbooks.',
  },
  {
    id: '18-iac',
    number: '18',
    title: 'Infrastructure as Code',
    route: '/iac',
    category: 'Operate',
    categoryIcon: '🔧',
    description: 'Modular Terraform/OpenTofu configurations for VPC, EKS, IAM, and Karpenter GPU provisioners.',
  },
  {
    id: '19-llm-pipelines',
    number: '19',
    title: 'LLM Pipelines (HF + LangChain)',
    route: '/llm-pipelines',
    category: 'Apps',
    categoryIcon: '🤖',
    description: 'Deploying end-to-end RAG and LangChain pipelines backed by Kubernetes GPU microservices.',
  },
];

export const CATEGORIES = [
  { name: 'Foundations', icon: '🏗️', chapterIds: ['00-prerequisites', '01-gpu-nodes', '02-gpu-operator', '03-gpu-sharing', '04-gpu-observability'] },
  { name: 'Data & Batch', icon: '📦', chapterIds: ['05-model-storage', '06-batch-kueue'] },
  { name: 'Training', icon: '🧠', chapterIds: ['07-distributed-training', '08-ray'] },
  { name: 'Serving', icon: '🚀', chapterIds: ['09-vllm-inference', '10-autoscaling-inference', '11-kserve', '12-inference-gateway'] },
  { name: 'Platform', icon: '⚙️', chapterIds: ['13-node-autoscaling', '14-security', '15-gitops', '16-capstone'] },
  { name: 'Operate', icon: '🔧', chapterIds: ['17-day2-ops', '18-iac'] },
  { name: 'Apps', icon: '🤖', chapterIds: ['19-llm-pipelines'] },
];

export function getChapterByPath(pathname = '') {
  if (!pathname) return null;
  // Strip trailing slashes and baseUrl
  const normalized = pathname.replace(/\/+$/, '');
  return CHAPTERS.find((ch) => {
    return normalized.endsWith(ch.route) || normalized.includes(ch.route + '/');
  }) || null;
}

export function getNextChapter(currentChapterId) {
  const idx = CHAPTERS.findIndex((c) => c.id === currentChapterId);
  if (idx !== -1 && idx < CHAPTERS.length - 1) {
    return CHAPTERS[idx + 1];
  }
  return null;
}

export function getPrevChapter(currentChapterId) {
  const idx = CHAPTERS.findIndex((c) => c.id === currentChapterId);
  if (idx > 0) {
    return CHAPTERS[idx - 1];
  }
  return null;
}
