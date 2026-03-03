import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  output: 'export',
  basePath: process.env.PAGES_BASE_PATH || '',
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
};

export default withMDX(config);