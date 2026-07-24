import { readdir, realpath } from "node:fs/promises";
import { basename, join, sep } from "node:path";

export type WorkspaceEntry = {
  name: string;
  path: string;
  kind: "root" | "directory";
};

export type WorkspaceListing = {
  path: string | null;
  entries: WorkspaceEntry[];
};

export class WorkspacePolicyError extends Error {
  constructor() {
    super("workspace not allowed");
    this.name = "WorkspacePolicyError";
  }
}

export class WorkspacePolicy {
  private configuredRoots: readonly string[];

  constructor(configuredRoots: readonly string[]) {
    this.configuredRoots = configuredRoots;
  }

  async assertAllowed(requestedPath: string): Promise<string> {
    let candidate: string;
    let roots: string[];
    try {
      [candidate, roots] = await Promise.all([
        realpath(requestedPath),
        this.canonicalRoots(),
      ]);
    } catch {
      throw new WorkspacePolicyError();
    }
    if (!roots.some((root) => isWithin(candidate, root))) {
      throw new WorkspacePolicyError();
    }
    return candidate;
  }

  async list(requestedPath?: string): Promise<WorkspaceListing> {
    if (!requestedPath) {
      const roots = await this.canonicalRoots();
      return {
        path: null,
        entries: roots.map((path) => ({
          name: basename(path),
          path,
          kind: "root",
        })),
      };
    }

    const path = await this.assertAllowed(requestedPath);
    const entries = await readdir(path, { withFileTypes: true });
    return {
      path,
      entries: entries
        .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
        .sort((left, right) => left.name.localeCompare(right.name))
        .slice(0, 100)
        .map((entry) => ({
          name: entry.name,
          path: join(path, entry.name),
          kind: "directory" as const,
        })),
    };
  }

  async roots(): Promise<string[]> {
    return this.canonicalRoots();
  }

  async replaceRoots(roots: readonly string[]): Promise<string[]> {
    let canonical: string[];
    try {
      canonical = await Promise.all(roots.map((root) => realpath(root)));
    } catch {
      throw new WorkspacePolicyError();
    }
    this.configuredRoots = [...new Set(canonical)].sort();
    return [...this.configuredRoots];
  }

  private async canonicalRoots(): Promise<string[]> {
    const roots = await Promise.all(
      this.configuredRoots.map((root) => realpath(root)),
    );
    return [...new Set(roots)].sort();
  }
}

function isWithin(candidate: string, root: string): boolean {
  return candidate === root || candidate.startsWith(`${root}${sep}`);
}
