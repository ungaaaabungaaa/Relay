import assert from "node:assert/strict";
import { mkdtemp, mkdir, realpath, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  WorkspacePolicy,
  WorkspacePolicyError,
} from "../src/workspaces/workspace-policy.ts";

describe("workspace policy", () => {
  it("lists an approved root and rejects a sibling path and escaping symlink", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-workspaces-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));

    const approvedRoot = join(temporary, "approved");
    const siblingRoot = join(temporary, "sibling");
    await mkdir(join(approvedRoot, "visible"), { recursive: true });
    await mkdir(join(approvedRoot, ".hidden"));
    await mkdir(siblingRoot);
    await symlink(siblingRoot, join(approvedRoot, "escape"));

    const policy = new WorkspacePolicy([approvedRoot]);
    const roots = await policy.list();
    assert.deepEqual(
      roots.entries.map((entry) => entry.name),
      ["approved"],
    );

    const listing = await policy.list(approvedRoot);
    assert.deepEqual(
      listing.entries.map((entry) => entry.name),
      ["visible"],
    );

    await assert.rejects(
      () => policy.list(siblingRoot),
      /workspace not allowed/,
    );
    await assert.rejects(
      () => policy.list(join(approvedRoot, "escape")),
      /workspace not allowed/,
    );
  });

  it("rejects task paths outside approved roots", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-workspaces-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));

    const approvedRoot = join(temporary, "approved");
    const siblingRoot = join(temporary, "sibling");
    const nested = join(approvedRoot, "nested");
    await mkdir(nested, { recursive: true });
    await mkdir(siblingRoot);

    const policy = new WorkspacePolicy([approvedRoot]);
    assert.equal(await policy.assertAllowed(nested), await realpath(nested));
    await assert.rejects(
      () => policy.assertAllowed(siblingRoot),
      /workspace not allowed/,
    );
    await assert.rejects(
      () => policy.assertAllowed(join(approvedRoot, "missing")),
      (error) => error instanceof WorkspacePolicyError,
    );
  });
});
