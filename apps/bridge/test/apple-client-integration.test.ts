import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";
import { EventHub } from "../src/events/event-hub.ts";
import { FakeCodexAdapter } from "./support/fake-codex-adapter.ts";
import { WatchTransportFixture } from "./support/watch-transport-fixture.ts";

async function createFixture() {
  const fakeCodex = new FakeCodexAdapter();
  const eventHub = new EventHub();
  const fixture = await WatchTransportFixture.create({
    fakeCodex,
    eventHub,
  });
  return { fakeCodex, eventHub, fixture };
}

describe("encrypted Apple client journey", () => {
  it("routes every snapshot and mutation through the encrypted bridge exactly once", async (context) => {
    const { fakeCodex, fixture } = await createFixture();
    context.after(() => fixture.close());

    assert.deepEqual(await fixture.request({ method: "GET", path: "/v1/tasks" }), {
      status: 200,
      body: {
        data: [fakeCodex.task],
        nextCursor: null,
      },
    });
    assert.deepEqual(
      await fixture.request({ method: "GET", path: "/v1/tasks/task-1" }),
      { status: 200, body: fakeCodex.taskDetail },
    );
    assert.deepEqual(await fixture.request({ method: "GET", path: "/v1/inbox" }), {
      status: 200,
      body: {
        approvals: [fakeCodex.approval],
        questions: [fakeCodex.question],
      },
    });
    assert.deepEqual(await fixture.request({ method: "GET", path: "/v1/models" }), {
      status: 200,
      body: { data: [fakeCodex.model] },
    });
    const folders = await fixture.request({ method: "GET", path: "/v1/folders" });
    assert.equal(folders.status, 200);
    assert.deepEqual(folders.body, {
      path: null,
      entries: [
        {
          name: "workspace",
          path: fixture.workspaceRoot,
          kind: "root",
        },
      ],
    });

    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/approvals/approval-1",
        body: { decision: "approve" },
        idempotencyKey: "approve-task-1-turn-1",
      }),
      { status: 200, body: { ok: true } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/questions/question-1",
        body: { answers: { "release-channel": ["Beta"] } },
        idempotencyKey: "answer-task-1-turn-1",
      }),
      { status: 200, body: { ok: true } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks",
        body: {
          cwd: fixture.workspaceRoot,
          model: "gpt-5",
          effort: "high",
          prompt: "Build the Watch client",
        },
        idempotencyKey: "start-watch-task-0001",
      }),
      { status: 201, body: { taskId: "task-created" } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/instructions",
        body: { text: "Run the focused tests" },
        idempotencyKey: "instruction-task-1-0001",
      }),
      { status: 200, body: { turnId: "turn-instruction" } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/steer",
        body: { turnId: "turn-1", text: "Keep the transport encrypted" },
        idempotencyKey: "steer-task-1-turn-1",
      }),
      { status: 200, body: { turnId: "turn-1" } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/stop",
        body: { turnId: "turn-1" },
        idempotencyKey: "stop-task-1-turn-1",
      }),
      { status: 200, body: { ok: true } },
    );
    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/stop",
        body: { turnId: "turn-1" },
        idempotencyKey: "stop-task-1-turn-1",
      }),
      { status: 200, body: { ok: true } },
    );

    assert.deepEqual(
      fakeCodex.calls.map((call) => call.operation),
      [
        "listTasks",
        "readTask",
        "listModels",
        "answerApproval",
        "answerQuestion",
        "listModels",
        "startTask",
        "sendInstruction",
        "steerTask",
        "stopTask",
      ],
    );
    assert.equal(
      fakeCodex.calls.filter((call) => call.operation === "stopTask").length,
      1,
    );
  });

  it("delivers an event interleaved with an encrypted response", async (context) => {
    const { fakeCodex, eventHub, fixture } = await createFixture();
    context.after(() => fixture.close());
    let published;
    fakeCodex.onCall = (call) => {
      if (call.operation === "stopTask") {
        published = eventHub.publish("task.updated", {
          threadId: "task-1",
          status: "idle",
        });
      }
    };

    const response = await fixture.request({
      method: "POST",
      path: "/v1/tasks/task-1/stop",
      body: { turnId: "turn-1" },
      idempotencyKey: "stop-event-task-1",
    });
    assert.deepEqual(response, { status: 200, body: { ok: true } });
    assert.deepEqual(await fixture.drainEvents(), [published]);
  });

  it("does not queue a disconnected mutation and refreshes snapshots after reconnect", async (context) => {
    const { fakeCodex, fixture } = await createFixture();
    context.after(() => fixture.close());
    fixture.disconnect();
    await assert.rejects(
      fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/stop",
        body: { turnId: "turn-1" },
        idempotencyKey: "stop-task-1-turn-1",
      }),
      /offline/,
    );
    assert.equal(fakeCodex.calls.length, 0);

    fakeCodex.task = { ...fakeCodex.task, title: "Refreshed after reconnect" };
    fixture.reconnect();
    const refreshed = await fixture.request({ method: "GET", path: "/v1/tasks" });
    assert.equal(
      (refreshed.body as { data: Array<{ title: string }> }).data[0]?.title,
      "Refreshed after reconnect",
    );
  });

  it("rejects a revoked Watch and Emergency Stop leaves Codex tasks untouched", async (context) => {
    const first = await createFixture();
    context.after(() => first.fixture.close());
    first.fixture.revoke();
    await assert.rejects(
      first.fixture.request({ method: "GET", path: "/v1/tasks" }),
      /revoked/,
    );
    assert.equal(first.fakeCodex.calls.length, 0);

    const emergency = await createFixture();
    await emergency.fixture.close();
    await assert.rejects(
      emergency.fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/stop",
        body: { turnId: "turn-1" },
        idempotencyKey: "emergency-stop-task-1",
      }),
      /offline/,
    );
    assert.equal(emergency.fakeCodex.calls.length, 0);
    assert.equal(emergency.fakeCodex.task.status, "running");
  });

  it("rejects replay and conflicting idempotency reuse", async (context) => {
    const { fakeCodex, fixture } = await createFixture();
    context.after(() => fixture.close());
    await fixture.request({ method: "GET", path: "/v1/tasks", sequence: 10 });
    await assert.rejects(
      fixture.request({ method: "GET", path: "/v1/models", sequence: 10 }),
      /replay/,
    );

    assert.deepEqual(
      await fixture.request({
        method: "POST",
        path: "/v1/tasks/task-1/stop",
        body: { turnId: "turn-1" },
        idempotencyKey: "conflicting-key-0001",
      }),
      { status: 200, body: { ok: true } },
    );
    const conflict = await fixture.request({
      method: "POST",
      path: "/v1/tasks/task-1/instructions",
      body: { text: "This must not execute" },
      idempotencyKey: "conflicting-key-0001",
    });
    assert.equal(conflict.status, 409);
    assert.match((conflict.body as { error: string }).error, /another action/);
    assert.equal(
      fakeCodex.calls.filter((call) => call.operation === "sendInstruction").length,
      0,
    );
  });

  it("assembles ordered encrypted voice chunks before transcription", async (context) => {
    let received = Buffer.alloc(0);
    const fakeCodex = new FakeCodexAdapter();
    const fixture = await WatchTransportFixture.create({
      fakeCodex,
      transcriber: {
        transcribe: async (path) => {
          received = await readFile(path);
          return "Run the focused tests";
        },
      },
    });
    context.after(() => fixture.close());
    const audio = Buffer.from("ordered-voice-chunks");

    assert.deepEqual(
      await fixture.sendVoice({
        audio,
        durationMs: 1_500,
        chunkBytes: 5,
      }),
      { status: 200, body: { transcript: "Run the focused tests" } },
    );
    assert.deepEqual(received, audio);
    assert.equal(fakeCodex.calls.length, 0);
  });
});
