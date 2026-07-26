import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { CodexAdapter } from "../src/codex/adapter.ts";
import {
  mapApproval,
  mapModel,
  mapQuestion,
  mapThread,
  mapThreadDetail,
} from "../src/codex/mappers.ts";

describe("Codex protocol mappers", () => {
  it("maps a thread without leaking protocol details", () => {
    assert.deepEqual(
      mapThread({
        id: "t1",
        name: "Relay build",
        preview: "Build the watch app",
        cwd: "/tmp/relay",
        updatedAt: 42,
        status: { type: "active", activeFlags: [] },
      }),
      {
        id: "t1",
        title: "Relay build",
        preview: "Build the watch app",
        cwd: "/tmp/relay",
        updatedAt: 42,
        status: "running",
      },
    );
  });

  it("maps a command approval with exact command and working directory", () => {
    const approval = mapApproval("req-1", {
      method: "item/commandExecution/requestApproval",
      params: {
        threadId: "t1",
        turnId: "turn1",
        itemId: "item1",
        startedAtMs: 10,
        command: "git push",
        cwd: "/tmp/relay",
        reason: "network",
      },
    });
    assert.equal(approval.kind, "command");
    assert.equal(approval.command, "git push");
    assert.equal(approval.cwd, "/tmp/relay");
    assert.equal(approval.risk, "dangerous");
    assert.deepEqual(approval.riskReasons, ["remote write"]);
  });

  it("maps user input questions and model efforts", () => {
    assert.equal(
      mapQuestion("req-2", {
        threadId: "t1",
        turnId: "turn1",
        itemId: "item1",
        autoResolutionMs: null,
        questions: [{ id: "choice", header: "Mode", question: "Choose", options: [] }],
      }).questions[0]?.id,
      "choice",
    );
    assert.deepEqual(
      mapModel({
        id: "gpt",
        model: "gpt",
        displayName: "GPT",
        description: "Test",
        hidden: false,
        supportedReasoningEfforts: [{ reasoningEffort: "high", description: "Deep" }],
        defaultReasoningEffort: "high",
        inputModalities: ["text"],
        supportsPersonality: false,
        additionalSpeedTiers: [],
        serviceTiers: [],
        defaultServiceTier: null,
        isDefault: true,
        upgrade: null,
        upgradeInfo: null,
        availabilityNux: null,
      }).efforts,
      ["high"],
    );
  });

  it("returns the newest fifty safe activity entries and preserves the active turn", async () => {
    const response = {
      thread: {
        id: "thread-1",
        name: "Relay build",
        preview: "Build the watch app",
        cwd: "/tmp/relay",
        updatedAt: 42,
        status: { type: "active", activeFlags: [] },
        turns: [
          {
            id: "turn-complete",
            status: "completed",
            startedAt: 100,
            completedAt: 110,
            items: Array.from({ length: 51 }, (_, index) => ({
              type: "commandExecution" as const,
              id: `command-${index}`,
              command: `echo ${index}`,
              cwd: "/tmp/relay",
              processId: null,
              source: "user" as never,
              status: "completed" as const,
              commandActions: [],
              aggregatedOutput: "private command output",
              exitCode: 0,
              durationMs: 1,
            })),
          },
          {
            id: "turn-active",
            status: "inProgress",
            startedAt: 200,
            completedAt: null,
            items: [
              {
                type: "userMessage" as const,
                id: "user-1",
                clientId: null,
                content: [{ type: "text" as const, text: "Ship it", text_elements: [] }],
              },
              {
                type: "agentMessage" as const,
                id: "assistant-1",
                text: "Working on it",
                phase: null,
                memoryCitation: null,
              },
              {
                type: "fileChange" as const,
                id: "file-1",
                changes: [{ path: "apps/bridge/src/server.ts", kind: "update", diff: "private diff" }],
                status: "inProgress" as const,
              },
              {
                type: "mcpToolCall" as const,
                id: "tool-1",
                server: "relay",
                tool: "verify",
                status: "completed" as const,
                arguments: { secret: "do not expose" },
                appContext: null,
                pluginId: null,
                result: null,
                error: null,
                durationMs: 1,
              },
            ],
          },
        ],
      },
    };

    const detail = mapThreadDetail(response as never);

    assert.equal(detail.activeTurnId, "turn-active");
    assert.equal(detail.activity.length, 50);
    assert.deepEqual(detail.activity[0], {
      id: "command-5",
      turnId: "turn-complete",
      kind: "command",
      title: "echo 5",
      detail: null,
      status: "succeeded",
      occurredAt: 100,
    });
    assert.deepEqual(detail.activity.at(-1), {
      id: "tool-1",
      turnId: "turn-active",
      kind: "tool",
      title: "relay/verify",
      detail: null,
      status: "succeeded",
      occurredAt: 200,
    });
    assert.equal(
      detail.activity.some((entry) => entry.detail?.includes("private") ?? false),
      false,
    );

    const client = {
      onNotification: () => undefined,
      onRequest: () => undefined,
      request: async (method: string, params: unknown) => {
        assert.equal(method, "thread/read");
        assert.deepEqual(params, { threadId: "thread-1", includeTurns: true });
        return response;
      },
    };
    const adapter = new CodexAdapter(client as never);
    assert.deepEqual(await adapter.readTask("thread-1"), detail);
  });
});
