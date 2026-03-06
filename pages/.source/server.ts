// @ts-nocheck
import * as __fd_glob_15 from "../content/docs/API/Handle.mdx?collection=docs"
import * as __fd_glob_14 from "../content/docs/API/Fragment.mdx?collection=docs"
import * as __fd_glob_13 from "../content/docs/API/Context.mdx?collection=docs"
import * as __fd_glob_12 from "../content/docs/API/Container.mdx?collection=docs"
import * as __fd_glob_11 from "../content/docs/API/Compose.mdx?collection=docs"
import * as __fd_glob_10 from "../content/docs/API/Component.mdx?collection=docs"
import * as __fd_glob_9 from "../content/docs/quick-start.mdx?collection=docs"
import * as __fd_glob_8 from "../content/docs/installation.mdx?collection=docs"
import * as __fd_glob_7 from "../content/docs/index.mdx?collection=docs"
import * as __fd_glob_6 from "../content/docs/create-new-store.mdx?collection=docs"
import * as __fd_glob_5 from "../content/docs/create-new-reusable-component.mdx?collection=docs"
import * as __fd_glob_4 from "../content/docs/create-new-reactive-container.mdx?collection=docs"
import * as __fd_glob_3 from "../content/docs/create-new-hook.mdx?collection=docs"
import * as __fd_glob_2 from "../content/docs/create-new-handle.mdx?collection=docs"
import * as __fd_glob_1 from "../content/docs/create-new-context.mdx?collection=docs"
import { default as __fd_glob_0 } from "../content/docs/meta.json?collection=docs"
import { server } from 'fumadocs-mdx/runtime/server';
import type * as Config from '../source.config';

const create = server<typeof Config, import("fumadocs-mdx/runtime/types").InternalTypeConfig & {
  DocData: {
  }
}>({"doc":{"passthroughs":["extractedReferences"]}});

export const docs = await create.docs("docs", "content/docs", {"meta.json": __fd_glob_0, }, {"create-new-context.mdx": __fd_glob_1, "create-new-handle.mdx": __fd_glob_2, "create-new-hook.mdx": __fd_glob_3, "create-new-reactive-container.mdx": __fd_glob_4, "create-new-reusable-component.mdx": __fd_glob_5, "create-new-store.mdx": __fd_glob_6, "index.mdx": __fd_glob_7, "installation.mdx": __fd_glob_8, "quick-start.mdx": __fd_glob_9, "API/Component.mdx": __fd_glob_10, "API/Compose.mdx": __fd_glob_11, "API/Container.mdx": __fd_glob_12, "API/Context.mdx": __fd_glob_13, "API/Fragment.mdx": __fd_glob_14, "API/Handle.mdx": __fd_glob_15, });