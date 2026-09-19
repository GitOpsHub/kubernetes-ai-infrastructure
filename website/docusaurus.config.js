// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Kubernetes AI Infrastructure',
  tagline: 'A hands-on course for running AI workloads on Kubernetes — GPU scheduling, training, LLM serving, autoscaling, and cost.',
  favicon: 'img/favicon.ico',

  // GitHub Pages deployment config
  // Change these to your GitHub username and repo name if you add a remote
  url: 'https://GitOpsHub.github.io',
  baseUrl: '/kubernetes-ai-infrastructure/',
  organizationName: 'GitOpsHub',
  projectName: 'kubernetes-ai-infrastructure',
  deploymentBranch: 'gh-pages',
  trailingSlash: false,

  onBrokenLinks: 'warn',
  onBrokenAnchors: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    mermaid: true,
    format: 'detect',
  },

  themes: [
    '@docusaurus/theme-mermaid',
    [
      require.resolve('@easyops-cn/docusaurus-search-local'),
      {
        hashed: true,
        indexBlog: false,
        docsRouteBasePath: '/',
        highlightSearchTermsOnTargetPage: true,
      },
    ],
  ],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          routeBasePath: '/',
          editUrl:
            'https://github.com/GitOpsHub/kubernetes-ai-infrastructure/tree/main/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/og-image.png',
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'K8s AI Infra',
        logo: {
          alt: 'Kubernetes AI Infrastructure',
          src: 'img/logo.svg',
          srcDark: 'img/logo-dark.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'courseSidebar',
            position: 'left',
            label: 'Course',
          },
          {
            type: 'custom-learningProgress',
            position: 'right',
          },
          {
            href: 'https://github.com/GitOpsHub/kubernetes-ai-infrastructure',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Course',
            items: [
              { label: 'Prerequisites', to: '/prerequisites' },
              { label: 'GPU Nodes', to: '/gpu-nodes' },
              { label: 'vLLM Inference', to: '/vllm-inference' },
              { label: 'Capstone', to: '/capstone' },
            ],
          },
          {
            title: 'Resources',
            items: [
              { label: 'Conventions', to: '/conventions' },
              {
                label: 'GitHub',
                href: 'https://github.com/GitOpsHub/kubernetes-ai-infrastructure',
              },
              {
                label: 'AWS EKS Docs',
                href: 'https://docs.aws.amazon.com/eks/',
              },
              {
                label: 'NVIDIA GPU Operator',
                href: 'https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Kubernetes AI Infrastructure. Built with Docusaurus.`,
      },
      prism: {
        theme: require('prism-react-renderer').themes.oneDark,
        darkTheme: require('prism-react-renderer').themes.oneDark,
        additionalLanguages: ['bash', 'yaml', 'hcl', 'python', 'json', 'toml'],
      },
      mermaid: {
        theme: { light: 'neutral', dark: 'dark' },
      },
    }),
};

module.exports = config;
