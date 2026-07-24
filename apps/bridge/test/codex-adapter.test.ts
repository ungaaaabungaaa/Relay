import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { mapApproval, mapModel, mapQuestion, mapThread } from "../src/codex/mappers.ts";

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
});
