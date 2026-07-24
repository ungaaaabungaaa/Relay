import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { it } from "node:test";
import { ActionExecutor } from "../src/actions/action-executor.ts";
import { SqliteStore } from "../src/store/sqlite-store.ts";

it("persists idempotent action results across bridge restarts", async (context) => {
  const temporary = await mkdtemp(join(tmpdir(), "relay-actions-"));
  context.after(() => rm(temporary, { recursive: true, force: true }));
  const databasePath = join(temporary, "relay.sqlite");
  const action = {
    deviceId: "watch-1",
    idempotencyKey: "persisted-action-0001",
    action: "task.stop",
    target: "thread-1",
  };
  let executions = 0;

  const first = await new ActionExecutor(new SqliteStore(databasePath)).run(
    action,
    () => ({ count: ++executions }),
  );
  const second = await new ActionExecutor(new SqliteStore(databasePath)).run(
    action,
    () => ({ count: ++executions }),
  );

  assert.deepEqual(first, { count: 1 });
  assert.deepEqual(second, first);
  assert.equal(executions, 1);
});
