const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '../..');
const DOCS_DIR = path.resolve(__dirname, '../docs');
const GITHUB_BLOB_BASE = 'https://github.com/GitOpsHub/kubernetes-ai-infrastructure/blob/main';

console.log(`📚 Syncing docs from ${REPO_ROOT} → ${DOCS_DIR}`);

if (fs.existsSync(DOCS_DIR)) {
  fs.rmSync(DOCS_DIR, { recursive: true, force: true });
}
fs.mkdirSync(DOCS_DIR, { recursive: true });

const CHAPTERS = [
  { folder: '00-prerequisites-and-cluster-setup', slug: '00-prerequisites', route: 'prerequisites', title: 'Prerequisites & Cluster Setup' },
  { folder: '01-gpu-nodes-and-scheduling', slug: '01-gpu-nodes', route: 'gpu-nodes', title: 'GPU Nodes & Scheduling' },
  { folder: '02-nvidia-gpu-operator', slug: '02-gpu-operator', route: 'gpu-operator', title: 'NVIDIA GPU Operator' },
  { folder: '03-gpu-sharing-and-dra', slug: '03-gpu-sharing', route: 'gpu-sharing', title: 'GPU Sharing & DRA' },
  { folder: '04-gpu-observability', slug: '04-gpu-observability', route: 'gpu-observability', title: 'GPU Observability' },
  { folder: '05-model-storage-and-data', slug: '05-model-storage', route: 'model-storage', title: 'Model Storage & Data' },
  { folder: '06-batch-jobs-and-kueue', slug: '06-batch-kueue', route: 'batch-kueue', title: 'Batch Jobs & Kueue' },
  { folder: '07-distributed-training-kubeflow-trainer', slug: '07-distributed-training', route: 'distributed-training', title: 'Distributed Training (Kubeflow Trainer)' },
  { folder: '08-ray-on-kubernetes', slug: '08-ray', route: 'ray', title: 'Ray on Kubernetes' },
  { folder: '09-llm-inference-with-vllm', slug: '09-vllm-inference', route: 'vllm-inference', title: 'LLM Inference with vLLM' },
  { folder: '10-autoscaling-inference', slug: '10-autoscaling-inference', route: 'autoscaling-inference', title: 'Autoscaling Inference' },
  { folder: '11-kserve', slug: '11-kserve', route: 'kserve', title: 'KServe' },
  { folder: '12-inference-gateway-and-multinode-serving', slug: '12-inference-gateway', route: 'inference-gateway', title: 'Inference Gateway & Multinode Serving' },
  { folder: '13-node-autoscaling-and-cost', slug: '13-node-autoscaling', route: 'node-autoscaling', title: 'Node Autoscaling & Cost' },
  { folder: '14-multi-tenancy-and-security', slug: '14-security', route: 'security', title: 'Multi-tenancy & Security' },
  { folder: '15-mlops-gitops-and-pipelines', slug: '15-gitops', route: 'gitops', title: 'GitOps & MLOps Pipelines' },
  { folder: '16-capstone-ai-platform', slug: '16-capstone', route: 'capstone', title: 'Capstone AI Platform' },
  { folder: '17-platform-day2-operations', slug: '17-day2-ops', route: 'day2-ops', title: 'Platform Day-2 Operations' },
  { folder: '18-infrastructure-as-code', slug: '18-iac', route: 'iac', title: 'Infrastructure as Code' },
  { folder: '19-llm-pipelines-huggingface-langchain', slug: '19-llm-pipelines', route: 'llm-pipelines', title: 'LLM Pipelines (HF + LangChain)' },
];

function prependFrontMatter(content, title, sidebarPos) {
  let body = content;
  if (body.startsWith('---')) {
    const secondDelim = body.indexOf('---', 3);
    if (secondDelim !== -1) {
      body = body.slice(secondDelim + 3).trim();
    }
  }
  return `---\ntitle: "${title}"\nsidebar_position: ${sidebarPos}\n---\n\n${body}`;
}

function rewriteLinks(content, currentFolder = null) {
  let res = content;

  // Rewrite CONVENTIONS and README links
  res = res.replace(/\(CONVENTIONS\.md\)/g, '(/kubernetes-ai-infrastructure/conventions)');
  res = res.replace(/\(\.\.\/CONVENTIONS\.md\)/g, '(/kubernetes-ai-infrastructure/conventions)');
  res = res.replace(/\(\.\.\/README\.md\)/g, '(/kubernetes-ai-infrastructure/)');
  res = res.replace(/\(\.\.\/CLAUDE\.md\)/g, `(${GITHUB_BLOB_BASE}/CLAUDE.md)`);
  res = res.replace(/\((\.\.\/)?AI_INFRASTRUCTURE_RESEARCH_AND_ARTICLES\.md([^)]*)\)/g, `(${GITHUB_BLOB_BASE}/AI_INFRASTRUCTURE_RESEARCH_AND_ARTICLES.md$2)`);
  res = res.replace(/\(env\.sh\.example\)/g, `(${GITHUB_BLOB_BASE}/env.sh.example)`);

  // Rewrite chapter references in markdown links
  for (const ch of CHAPTERS) {
    // Relative link from root: (00-prerequisites-and-cluster-setup/) -> (/kubernetes-ai-infrastructure/prerequisites)
    const rootReg = new RegExp(`\\(${ch.folder}\\/?(?:README\\.md)?\\)`, 'g');
    res = res.replace(rootReg, `(/kubernetes-ai-infrastructure/${ch.route})`);

    // Relative link from another chapter: (../00-prerequisites-and-cluster-setup/?) -> (/kubernetes-ai-infrastructure/prerequisites)
    const relReg = new RegExp(`\\(\\.\\.\\/${ch.folder}\\/?(?:README\\.md)?\\)`, 'g');
    res = res.replace(relReg, `(/kubernetes-ai-infrastructure/${ch.route})`);

    // Cross-chapter links to code files: (../00-prerequisites-and-cluster-setup/eks/cluster.yaml) -> GitHub URL
    const crossCodeReg = new RegExp(`\\(\\.\\.\\/${ch.folder}\\/([^)]+\\.(yaml|yml|sh|py|tf|env|json))\\)`, 'g');
    res = res.replace(crossCodeReg, `(${GITHUB_BLOB_BASE}/${ch.folder}/$1)`);
  }

  // Links to root files like (scripts/validate-all.sh), (versions.env), (CLAUDE.md), (.github/...)
  res = res.replace(/\((scripts\/[^)]+)\)/g, `(${GITHUB_BLOB_BASE}/$1)`);
  res = res.replace(/\((\.\.\/)?versions\.env\)/g, `(${GITHUB_BLOB_BASE}/versions.env)`);
  res = res.replace(/\((\.\.\/)?CLAUDE\.md\)/g, `(${GITHUB_BLOB_BASE}/CLAUDE.md)`);
  res = res.replace(/\((\.\.\/)?\.github\/([^)]+)\)/g, `(${GITHUB_BLOB_BASE}/.github/$2)`);

  // If in a specific chapter, rewrite intra-chapter relative code links like (eks/cluster.yaml), (cpu-lab/...)
  if (currentFolder) {
    res = res.replace(/\(((?:eks|cpu-lab|manifests|charts|src|tests|docker)\/[^)]+)\)/g, `(${GITHUB_BLOB_BASE}/${currentFolder}/$1)`);
    // Local standalone file links like (cluster.yaml)
    res = res.replace(/\(([a-zA-Z0-9_.-]+\.(?:yaml|yml|sh|py|tf|env|json))\)/g, `(${GITHUB_BLOB_BASE}/${currentFolder}/$1)`);
  }

  return res;
}

// 1. Root docs
const rootReadme = fs.readFileSync(path.join(REPO_ROOT, 'README.md'), 'utf8');
const processedRootReadme = rewriteLinks(rootReadme);
fs.writeFileSync(path.join(DOCS_DIR, 'index.md'), prependFrontMatter(processedRootReadme, 'Course Overview', 1));

const conventions = fs.readFileSync(path.join(REPO_ROOT, 'CONVENTIONS.md'), 'utf8');
const processedConventions = rewriteLinks(conventions);
fs.writeFileSync(path.join(DOCS_DIR, 'conventions.md'), prependFrontMatter(processedConventions, 'Conventions & Setup', 2));

// 2. Chapters
let pos = 10;
for (const ch of CHAPTERS) {
  const readmePath = path.join(REPO_ROOT, ch.folder, 'README.md');
  if (!fs.existsSync(readmePath)) {
    console.warn(`  ⚠️  No README.md in ${ch.folder}, skipping`);
    continue;
  }

  const destDir = path.join(DOCS_DIR, ch.slug);
  fs.mkdirSync(destDir, { recursive: true });

  const raw = fs.readFileSync(readmePath, 'utf8');
  const processed = rewriteLinks(raw, ch.folder);
  fs.writeFileSync(path.join(destDir, 'index.md'), prependFrontMatter(processed, ch.title, pos));
  console.log(`  ✅ ${ch.folder} → docs/${ch.slug}/index.md  (pos=${pos})`);
  pos++;
}

// 3. Chapter 19 extra LangChain docs
const langchainSrc = path.join(REPO_ROOT, '19-llm-pipelines-huggingface-langchain/common/src/langchain_app/docs');
const langchainDst = path.join(DOCS_DIR, '19-llm-pipelines');

if (fs.existsSync(langchainSrc)) {
  const files = fs.readdirSync(langchainSrc).filter(f => f.endsWith('.md'));
  for (const f of files) {
    const raw = fs.readFileSync(path.join(langchainSrc, f), 'utf8');
    const processed = rewriteLinks(raw, '19-llm-pipelines-huggingface-langchain');
    const slugTitle = f.replace('.md', '').split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    fs.writeFileSync(path.join(langchainDst, f), prependFrontMatter(processed, slugTitle, 99));
    console.log(`  ✅ langchain-docs/${f}`);
  }
}

console.log(`\n✨ Done! Synced documentation successfully.`);
