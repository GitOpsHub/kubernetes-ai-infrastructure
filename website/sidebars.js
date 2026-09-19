/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  courseSidebar: [
    {
      type: 'doc',
      id: 'index',
      label: '🏠 Course Overview',
    },
    {
      type: 'doc',
      id: 'conventions',
      label: '📋 Conventions & Setup',
    },
    {
      type: 'category',
      label: '🏗️ Foundations',
      collapsed: false,
      items: [
        { type: 'doc', id: 'prerequisites/index',      label: '00 · Prerequisites & Cluster Setup' },
        { type: 'doc', id: 'gpu-nodes/index',          label: '01 · GPU Nodes & Scheduling' },
        { type: 'doc', id: 'gpu-operator/index',       label: '02 · NVIDIA GPU Operator' },
        { type: 'doc', id: 'gpu-sharing/index',        label: '03 · GPU Sharing & DRA' },
        { type: 'doc', id: 'gpu-observability/index',  label: '04 · GPU Observability' },
      ],
    },
    {
      type: 'category',
      label: '📦 Data & Batch',
      collapsed: false,
      items: [
        { type: 'doc', id: 'model-storage/index',      label: '05 · Model Storage & Data' },
        { type: 'doc', id: 'batch-kueue/index',        label: '06 · Batch Jobs & Kueue' },
      ],
    },
    {
      type: 'category',
      label: '🧠 Training',
      collapsed: false,
      items: [
        { type: 'doc', id: 'distributed-training/index', label: '07 · Distributed Training (Kubeflow Trainer)' },
        { type: 'doc', id: 'ray/index',                  label: '08 · Ray on Kubernetes' },
      ],
    },
    {
      type: 'category',
      label: '🚀 Serving',
      collapsed: false,
      items: [
        { type: 'doc', id: 'vllm-inference/index',         label: '09 · LLM Inference with vLLM' },
        { type: 'doc', id: 'autoscaling-inference/index',  label: '10 · Autoscaling Inference' },
        { type: 'doc', id: 'kserve/index',                 label: '11 · KServe' },
        { type: 'doc', id: 'inference-gateway/index',      label: '12 · Inference Gateway & Multi-node Serving' },
      ],
    },
    {
      type: 'category',
      label: '⚙️ Platform',
      collapsed: false,
      items: [
        { type: 'doc', id: 'node-autoscaling/index',  label: '13 · Node Autoscaling & Cost' },
        { type: 'doc', id: 'security/index',          label: '14 · Multi-tenancy & Security' },
        { type: 'doc', id: 'gitops/index',            label: '15 · GitOps & MLOps Pipelines' },
        { type: 'doc', id: 'capstone/index',          label: '16 · Capstone AI Platform' },
      ],
    },
    {
      type: 'category',
      label: '🔧 Operate',
      collapsed: false,
      items: [
        { type: 'doc', id: 'day2-ops/index',  label: '17 · Platform Day-2 Operations' },
        { type: 'doc', id: 'iac/index',       label: '18 · Infrastructure as Code' },
      ],
    },
    {
      type: 'category',
      label: '🤖 Apps',
      collapsed: false,
      items: [
        { type: 'doc', id: 'llm-pipelines/index', label: '19 · LLM Pipelines (HF + LangChain)' },
        {
          type: 'category',
          label: 'LangChain App Docs',
          collapsed: true,
          items: [
            { type: 'doc', id: 'llm-pipelines/spot-gpu-nodes',    label: 'Spot GPU Nodes' },
            { type: 'doc', id: 'llm-pipelines/kueue-gpu-queues',  label: 'Kueue GPU Queues' },
            { type: 'doc', id: 'llm-pipelines/model-storage',     label: 'Model Storage' },
            { type: 'doc', id: 'llm-pipelines/vllm-serving',      label: 'vLLM Serving' },
            { type: 'doc', id: 'llm-pipelines/keda-autoscaling',  label: 'KEDA Autoscaling' },
          ],
        },
      ],
    },
  ],
};

module.exports = sidebars;
