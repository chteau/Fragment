// @ts-nocheck
import { browser } from 'fumadocs-mdx/runtime/browser';
import type * as Config from '../source.config';

const create = browser<typeof Config, import("fumadocs-mdx/runtime/types").InternalTypeConfig & {
  DocData: {
  }
}>();
const browserCollections = {
  docs: create.doc("docs", {"create-new-context.mdx": () => import("../content/docs/create-new-context.mdx?collection=docs"), "create-new-handle.mdx": () => import("../content/docs/create-new-handle.mdx?collection=docs"), "create-new-hook.mdx": () => import("../content/docs/create-new-hook.mdx?collection=docs"), "create-new-reactive-container.mdx": () => import("../content/docs/create-new-reactive-container.mdx?collection=docs"), "create-new-reusable-component.mdx": () => import("../content/docs/create-new-reusable-component.mdx?collection=docs"), "create-new-store.mdx": () => import("../content/docs/create-new-store.mdx?collection=docs"), "index.mdx": () => import("../content/docs/index.mdx?collection=docs"), "installation.mdx": () => import("../content/docs/installation.mdx?collection=docs"), "quick-start.mdx": () => import("../content/docs/quick-start.mdx?collection=docs"), "API/Component.mdx": () => import("../content/docs/API/Component.mdx?collection=docs"), "API/Compose.mdx": () => import("../content/docs/API/Compose.mdx?collection=docs"), "API/Container.mdx": () => import("../content/docs/API/Container.mdx?collection=docs"), "API/Context.mdx": () => import("../content/docs/API/Context.mdx?collection=docs"), "API/Fragment.mdx": () => import("../content/docs/API/Fragment.mdx?collection=docs"), "API/Handle.mdx": () => import("../content/docs/API/Handle.mdx?collection=docs"), }),
};
export default browserCollections;