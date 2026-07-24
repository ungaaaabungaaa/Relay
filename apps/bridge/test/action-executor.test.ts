import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ActionExecutor,
  IdempotencyConflictError,
  ActionInProgressError,
} from "../src/actions/action-executor.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";

describe("idempotent action executor", () => {
  it("executes a repeated action once and returns the first result", async () => {
    const store = new InMemorySecurityStore();
    const executor = new ActionExecutor(store);
    const context = {
      deviceId: "watch-1",
      idempotencyKey: "approval-request-0001",
      action: "approval.approve",
      target: "approval-1",
    };
    let executions = 0;

    const first = await executor.run(context, () => ({
      count: ++executions,
    }));
    const second = await executor.run(context, () => ({
      count: ++executions,
    }));

    assert.deepEqual(first, { count: 1 });
    assert.deepEqual(second, first);
    assert.equal(executions, 1);
    assert.deepEqual(store.auditEvents, [
      {
        deviceId: "watch-1",
        action: "approval.approve",
        target: "approval-1",
        result: "succeeded",
      },
    ]);
  });

  it("does not execute a duplicate while the first action is pending", async () => {
    const store = new InMemorySecurityStore();
    const executor = new ActionExecutor(store);
    const context = {
      deviceId: "watch-1",
      idempotencyKey: "approval-request-0002",
      action: "approval.approve",
      target: "approval-2",
    };
    let release: (() => void) | undefined;
    let executions = 0;
    const pending = executor.run(context, async () => {
      executions += 1;
      await new Promise<void>((resolve) => {
        release = resolve;
      });
      return { ok: true };
    });

    await assert.rejects(
      () => executor.run(context, () => ({ ok: false })),
      ActionInProgressError,
    );
    assert.equal(executions, 1);
    release?.();
    await pending;
  });

  it("rejects reuse of one key for a different action", async () => {
    const store = new InMemorySecurityStore();
    const executor = new ActionExecutor(store);
    const original = {
      deviceId: "watch-1",
      idempotencyKey: "shared-action-key-0001",
      action: "approval.approve",
      target: "approval-1",
    };
    await executor.run(original, () => ({ ok: true }));

    await assert.rejects(
      () =>
        executor.run(
          {
            ...original,
            action: "task.stop",
            target: "thread-1",
          },
          () => ({ stopped: true }),
        ),
      IdempotencyConflictError,
    );
  });
});
