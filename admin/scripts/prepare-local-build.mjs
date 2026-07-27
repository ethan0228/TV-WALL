import { readFile, writeFile } from "node:fs/promises";

const configPath = new URL("../dist/server/wrangler.json", import.meta.url);
const config = JSON.parse(await readFile(configPath, "utf8"));

// vinext emits several sibling ES modules that Wrangler loads without bundling.
// Preserve their filenames so imports such as ./__vite_rsc_assets_manifest.js
// resolve consistently in the local macOS service.
config.find_additional_modules = true;
config.preserve_file_names = true;
config.base_dir = ".";

await writeFile(configPath, `${JSON.stringify(config)}\n`);
