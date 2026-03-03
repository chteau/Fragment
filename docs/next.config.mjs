import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  output: 'export',
  basePath: '/Fragment',
  assetPrefix: '/Fragment/',
  trailingSlash: true,
  images: {
    unoptimized: true, // required for static export
  },
};

export default withMDX(config);
