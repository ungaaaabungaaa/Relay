import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRequestHandler } from "../src/server.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

const fakeAdapter = {
  listTasks: async () => ({ data: [{ id: "secret-task" }], nextCursor: null }),
  readTask: async () => ({}),
  listModels: async () => [
    {
      id: "gpt",
      name: "GPT",
      description: "Test model",
      efforts: ["high"],
      defaultEffort: "high",
      isDefault: true,
    },
  ],
  approvals: () => [],
  questions: () => [],
};

function signedMutation(
  privateKey: ReturnType<typeof generateKeyPairSync>["privateKey"],
  path: string,
  body: Buffer,
  idempotencyKey: string,
  nonce: string,
) {
  const timestamp = Date.now();
  const signature = sign(
    null,
    Buffer.from(
      canonicalRequest({
        deviceId: "watch",
        method: "POST",
        path,
        body,
        timestamp,
        nonce,
      }),
    ),
    privateKey,
  ).toString("base64");
  return new Request(`http://localhost${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "idempotency-key": idempotencyKey,
      "x-relay-device": "watch",
      "x-relay-timestamp": String(timestamp),
      "x-relay-nonce": nonce,
      "x-relay-signature": signature,
    },
    body,
  });
}

describe("bridge API", () => {
  it("returns a metadata-free health response", async () => {
    const handler = createRequestHandler({
      store: new InMemorySecurityStore(),
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
    });
    const response = await handler(new Request("http://localhost/health"));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, service: "relay" });
  });

  it("rejects unauthenticated task access", async () => {
    const handler = createRequestHandler({
      store: new InMemorySecurityStore(),
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
    });
    const response = await handler(new Request("http://localhost/v1/tasks"));
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: "unauthorized" });
  });

  it("returns tasks to a correctly signed device", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice("watch", publicKey.export({ type: "spki", format: "pem" }).toString());
    const timestamp = Date.now();
    const signed = {
      deviceId: "watch",
      method: "GET",
      path: "/v1/tasks",
      body: new Uint8Array(),
      timestamp,
      nonce: "signed-nonce-1234",
    };
    const signature = sign(null, Buffer.from(canonicalRequest(signed)), privateKey).toString("base64");
    const handler = createRequestHandler({
      store,
      adapter: fakeAdapter,
      workspacePolicy: new WorkspacePolicy([]),
    });
    const response = await handler(
      new Request("http://localhost/v1/tasks", {
        headers: {
          "x-relay-device": "watch",
          "x-relay-timestamp": String(timestamp),
          "x-relay-nonce": signed.nonce,
          "x-relay-signature": signature,
        },
      }),
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).data[0].id, "secret-task");
  });

  it("rejects folder browsing and task creation outside approved roots", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-server-workspaces-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));
    const approvedRoot = join(temporary, "approved");
    const siblingRoot = join(temporary, "sibling");
    await mkdir(approvedRoot);
    await mkdir(siblingRoot);

    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let startCalls = 0;
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        startTask: async () => {
          startCalls += 1;
          return {};
        },
      },
      workspacePolicy: new WorkspacePolicy([approvedRoot]),
    });

    const folderPath = `/v1/folders?path=${encodeURIComponent(siblingRoot)}`;
    const folderTimestamp = Date.now();
    const folderNonce = "folder-policy-nonce";
    const folderSignature = sign(
      null,
      Buffer.from(
        canonicalRequest({
          deviceId: "watch",
          method: "GET",
          path: folderPath,
          body: new Uint8Array(),
          timestamp: folderTimestamp,
          nonce: folderNonce,
        }),
      ),
      privateKey,
    ).toString("base64");
    const folderResponse = await handler(
      new Request(`http://localhost${folderPath}`, {
        headers: {
          "x-relay-device": "watch",
          "x-relay-timestamp": String(folderTimestamp),
          "x-relay-nonce": folderNonce,
          "x-relay-signature": folderSignature,
        },
      }),
    );
    assert.equal(folderResponse.status, 403);
    assert.deepEqual(await folderResponse.json(), {
      error: "workspace not allowed",
    });

    const body = Buffer.from(
      JSON.stringify({
        cwd: siblingRoot,
        model: "gpt",
        effort: "high",
        prompt: "Build Relay",
      }),
    );
    const taskTimestamp = Date.now();
    const taskNonce = "task-policy-nonce";
    const taskSignature = sign(
      null,
      Buffer.from(
        canonicalRequest({
          deviceId: "watch",
          method: "POST",
          path: "/v1/tasks",
          body,
          timestamp: taskTimestamp,
          nonce: taskNonce,
        }),
      ),
      privateKey,
    ).toString("base64");
    const taskResponse = await handler(
      new Request("http://localhost/v1/tasks", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "idempotency-key": "workspace-task-0001",
          "x-relay-device": "watch",
          "x-relay-timestamp": String(taskTimestamp),
          "x-relay-nonce": taskNonce,
          "x-relay-signature": taskSignature,
        },
        body,
      }),
    );
    assert.equal(taskResponse.status, 403);
    assert.equal(startCalls, 0);
  });

  it("requires an idempotency key before invoking a mutating route", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let approvalCalls = 0;
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        approvals: () => [
          {
            id: "approval-1",
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            kind: "command" as const,
            risk: "normal" as const,
            riskReasons: [],
            command: "pnpm test",
            cwd: "/tmp/relay",
            reason: null,
            startedAtMs: 1,
          },
        ],
        answerApproval: () => {
          approvalCalls += 1;
        },
      },
      workspacePolicy: new WorkspacePolicy([]),
    });
    const body = Buffer.from(JSON.stringify({ decision: "approve" }));
    const timestamp = Date.now();
    const nonce = "missing-idempotency-key";
    const signature = sign(
      null,
      Buffer.from(
        canonicalRequest({
          deviceId: "watch",
          method: "POST",
          path: "/v1/approvals/approval-1",
          body,
          timestamp,
          nonce,
        }),
      ),
      privateKey,
    ).toString("base64");

    const response = await handler(
      new Request("http://localhost/v1/approvals/approval-1", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-relay-device": "watch",
          "x-relay-timestamp": String(timestamp),
          "x-relay-nonce": nonce,
          "x-relay-signature": signature,
        },
        body,
      }),
    );

    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {
      error: "invalid idempotency key",
    });
    assert.equal(approvalCalls, 0);
  });

  it("rejects unsafe approval decisions and question options before invoking Codex", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let approvalCalls = 0;
    let questionCalls = 0;
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        approvals: () => [
          {
            id: "approval-dangerous",
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            kind: "command" as const,
            risk: "dangerous" as const,
            riskReasons: ["remote write"],
            command: "git push",
            cwd: "/tmp/relay",
            reason: null,
            startedAtMs: 1,
          },
        ],
        questions: () => [
          {
            id: "question-1",
            threadId: "thread-1",
            turnId: "turn-1",
            itemId: "item-1",
            questions: [
              {
                id: "release-channel",
                header: "Release channel",
                question: "Choose one",
                options: [{ label: "Beta", description: "Test build" }],
              },
            ],
          },
        ],
        answerApproval: () => {
          approvalCalls += 1;
        },
        answerQuestion: () => {
          questionCalls += 1;
        },
      },
      workspacePolicy: new WorkspacePolicy([]),
    });

    const dangerous = Buffer.from(JSON.stringify({ decision: "approve" }));
    const dangerousResponse = await handler(
      signedMutation(
        privateKey,
        "/v1/approvals/approval-dangerous",
        dangerous,
        "dangerous-approval-0001",
        "dangerous-approval-nonce",
      ),
    );
    assert.equal(dangerousResponse.status, 400);
    assert.match((await dangerousResponse.json()).error, /confirmation required/);
    assert.equal(approvalCalls, 0);

    const invalidAnswer = Buffer.from(
      JSON.stringify({ answers: { "release-channel": ["Production"] } }),
    );
    const questionResponse = await handler(
      signedMutation(
        privateKey,
        "/v1/questions/question-1",
        invalidAnswer,
        "question-answer-0001",
        "question-answer-nonce",
      ),
    );
    assert.equal(questionResponse.status, 400);
    assert.match((await questionResponse.json()).error, /unknown option/);
    assert.equal(questionCalls, 0);
  });

  it("rejects unknown model and effort combinations before starting a task", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-server-new-task-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let startCalls = 0;
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        listModels: async () => [
          {
            id: "gpt",
            name: "GPT",
            description: "Test model",
            efforts: ["low", "high"],
            defaultEffort: "high",
            isDefault: true,
          },
        ],
        startTask: async () => {
          startCalls += 1;
          return { thread: { id: "thread-created" } };
        },
      },
      workspacePolicy: new WorkspacePolicy([temporary]),
    });

    for (const [model, effort, key, nonce] of [
      ["missing", "high", "new-task-model-0001", "new-task-model-nonce"],
      ["gpt", "maximum", "new-task-effort-0001", "new-task-effort-nonce"],
    ]) {
      const body = Buffer.from(
        JSON.stringify({ cwd: temporary, model, effort, prompt: "Build Relay" }),
      );
      const response = await handler(
        signedMutation(privateKey, "/v1/tasks", body, key, nonce),
      );
      assert.equal(response.status, 400);
    }
    assert.equal(startCalls, 0);
  });

  it("returns a stable task identifier after starting a validated task", async (context) => {
    const temporary = await mkdtemp(join(tmpdir(), "relay-server-task-ack-"));
    context.after(() => rm(temporary, { recursive: true, force: true }));
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        listModels: async () => [
          {
            id: "gpt",
            name: "GPT",
            description: "Test model",
            efforts: ["high"],
            defaultEffort: "high",
            isDefault: true,
          },
        ],
        startTask: async () => ({ thread: { id: "thread-created" } }),
      },
      workspacePolicy: new WorkspacePolicy([temporary]),
    });
    const body = Buffer.from(
      JSON.stringify({ cwd: temporary, model: "gpt", effort: "high", prompt: "Build Relay" }),
    );
    const response = await handler(
      signedMutation(
        privateKey,
        "/v1/tasks",
        body,
        "new-task-valid-0001",
        "new-task-valid-nonce",
      ),
    );

    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { taskId: "thread-created" });
  });

  it("returns the first approval result without invoking Codex twice", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let approvalCalls = 0;
    let approvals = [
      {
        id: "approval-1",
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        kind: "command" as const,
        risk: "normal" as const,
        riskReasons: [],
        command: "pnpm test",
        cwd: "/tmp/relay",
        reason: null,
        startedAtMs: 1,
      },
    ];
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        approvals: () => approvals,
        answerApproval: () => {
          approvalCalls += 1;
          approvals = [];
        },
      },
      workspacePolicy: new WorkspacePolicy([]),
    });
    const body = Buffer.from(JSON.stringify({ decision: "approve" }));
    const makeRequest = (nonce: string) => {
      const timestamp = Date.now();
      const signature = sign(
        null,
        Buffer.from(
          canonicalRequest({
            deviceId: "watch",
            method: "POST",
            path: "/v1/approvals/approval-1",
            body,
            timestamp,
            nonce,
          }),
        ),
        privateKey,
      ).toString("base64");
      return new Request("http://localhost/v1/approvals/approval-1", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "idempotency-key": "approval-request-0001",
          "x-relay-device": "watch",
          "x-relay-timestamp": String(timestamp),
          "x-relay-nonce": nonce,
          "x-relay-signature": signature,
        },
        body,
      });
    };

    const first = await handler(makeRequest("approval-first-nonce"));
    const second = await handler(makeRequest("approval-second-nonce"));

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.deepEqual(await second.json(), { ok: true });
    assert.equal(approvalCalls, 1);
  });

  it("returns the first question result after the pending question is consumed", async () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const store = new InMemorySecurityStore();
    store.addDevice(
      "watch",
      publicKey.export({ type: "spki", format: "pem" }).toString(),
    );
    let answerCalls = 0;
    let questions = [
      {
        id: "question-1",
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: [
          {
            id: "release-channel",
            header: "Release channel",
            question: "Choose one",
            options: [{ label: "Beta", description: "Test build" }],
          },
        ],
      },
    ];
    const handler = createRequestHandler({
      store,
      adapter: {
        ...fakeAdapter,
        questions: () => questions,
        answerQuestion: () => {
          answerCalls += 1;
          questions = [];
        },
      },
      workspacePolicy: new WorkspacePolicy([]),
    });
    const body = Buffer.from(
      JSON.stringify({ answers: { "release-channel": ["Beta"] } }),
    );

    const first = await handler(
      signedMutation(
        privateKey,
        "/v1/questions/question-1",
        body,
        "question-retry-0001",
        "question-retry-first-nonce",
      ),
    );
    const second = await handler(
      signedMutation(
        privateKey,
        "/v1/questions/question-1",
        body,
        "question-retry-0001",
        "question-retry-second-nonce",
      ),
    );

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.deepEqual(await second.json(), { ok: true });
    assert.equal(answerCalls, 1);
  });
});
