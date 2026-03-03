import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  output: 'export',
  basePath: process.env.PAGES_BASE_PATH ?? '',
  assetPrefix: process.env.PAGES_BASE_PATH ?? '',
  images: {
    unoptimized: true, // required for static export
  },
};

export default withMDX(config);
