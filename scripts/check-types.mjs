import { readdirSync, statSync } from "node:fs";
import { resolve } from "node:path";
import ts from "typescript";

function collect(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (
      entry.isDirectory() &&
      !["node_modules", "generated", "build"].includes(entry.name)
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
  const source = ts.sys.readFile(file);
  if (source === undefined) {
    process.stderr.write(`Unable to read ${file}\n`);
    process.exit(1);
  }
  const result = ts.transpileModule(source, {
    fileName: file,
    reportDiagnostics: true,
    compilerOptions: {
      erasableSyntaxOnly: true,
      module: ts.ModuleKind.NodeNext,
      moduleResolution: ts.ModuleResolutionKind.NodeNext,
      target: ts.ScriptTarget.ES2022,
    },
  });
  const errors = (result.diagnostics ?? []).filter(
    (diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error,
  );
  if (errors.length > 0) {
    process.stderr.write(
      ts.formatDiagnosticsWithColorAndContext(errors, {
        getCanonicalFileName: (name) => name,
        getCurrentDirectory: () => process.cwd(),
        getNewLine: () => "\n",
      }),
    );
    process.exit(1);
  }
}

console.log("TypeScript syntax and erasable-type checks passed");
