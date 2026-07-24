import { readdirSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

function collect(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (
      entry.isDirectory() &&
      !["node_modules", "generated", "build", ".gradle"].includes(entry.name)
    ) {
      files.push(...collect(path));
    } else if (entry.isFile() && path.endsWith(".ts")) {
      files.push(path);
    }
  }
  return files;
}

const roots = ["apps", "packages"]
  .map((path) => resolve(path))
  .filter((path) => {
    try {
      return statSync(path).isDirectory();
    } catch {
      return false;
    }
  });

for (const file of roots.flatMap(collect)) {
  const checked = spawnSync(
    process.execPath,
    ["--experimental-strip-types", "--check", file],
    { encoding: "utf8" },
  );
  if (checked.status !== 0) {
    process.stderr.write(checked.stderr);
    process.exit(checked.status ?? 1);
  }
}

console.log("TypeScript syntax and erasable-type checks passed");
