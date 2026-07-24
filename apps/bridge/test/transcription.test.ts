import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { canonicalRequest } from "../src/security/authentication.ts";
import { InMemorySecurityStore } from "../src/security/store.ts";
import { createRequestHandler } from "../src/server.ts";
import { transcribeAudio } from "../src/transcription/transcriber.ts";
import { WorkspacePolicy } from "../src/workspaces/workspace-policy.ts";

describe("temporary audio transcription", () => {
  it("deletes the temporary file after successful transcription", async () => {
    await withTemporaryDirectory(async (directory) => {
      let receivedPath = "";
      const result = await transcribeAudio({
        audio: new Uint8Array([1, 2, 3]),
        contentType: "audio/mp4",
        durationMs: 2_000,
        temporaryDirectory: directory,
        transcriber: {
          async transcribe(filePath) {
            receivedPath = filePath;
            assert.deepEqual(await readdir(directory), [filePath.split("/").at(-1)]);
            return "review this transcript";
          },
        },
      });

      assert.equal(result, "review this transcript");
      assert.ok(receivedPath);
      assert.deepEqual(await readdir(directory), []);
    });
  });

  it("deletes the temporary file after provider failure and timeout", async () => {
    await withTemporaryDirectory(async (directory) => {
      await assert.rejects(
        transcribeAudio({
          audio: new Uint8Array([1]),
          contentType: "audio/mp4",
          durationMs: 1_000,
          temporaryDirectory: directory,
          transcriber: {
            async transcribe() {
              throw new Error("provider unavailable");
            },
          },
        }),
        /provider unavailable/,
      );
      assert.deepEqual(await readdir(directory), []);

      await assert.rejects(
        transcribeAudio({
          audio: new Uint8Array([1]),
          contentType: "audio/mp4",
          durationMs: 1_000,
          temporaryDirectory: directory,
          timeoutMs: 5,
          transcriber: {
            async transcribe() {
              return await new Promise<string>(() => {});
            },
          },
        }),
        /timed out/,
      );
      assert.deepEqual(await readdir(directory), []);
    });
  });

  it("rejects invalid media, duration, and size without invoking the provider", async () => {
    await withTemporaryDirectory(async (directory) => {
      let invocations = 0;
      const transcriber = {
        async transcribe() {
          invocations += 1;
          return "never";
        },
      };
      const base = {
        audio: new Uint8Array([1]),
        contentType: "audio/mp4",
        durationMs: 1_000,
        temporaryDirectory: directory,
        transcriber,
      };

      await assert.rejects(
        transcribeAudio({ ...base, contentType: "text/plain" }),
        /unsupported audio type/,
      );
      await assert.rejects(
        transcribeAudio({ ...base, durationMs: 30_001 }),
        /audio duration exceeds 30 seconds/,
      );
      await assert.rejects(
        transcribeAudio({
          ...base,
          audio: new Uint8Array(2 * 1024 * 1024 + 1),
        }),
        /audio exceeds 2 MiB/,
      );
      assert.equal(invocations, 0);
      assert.deepEqual(await readdir(directory), []);
    });
  });

  it("exposes transcription only through an authenticated signed upload", async () => {
    await withTemporaryDirectory(async (directory) => {
      const { publicKey, privateKey } = generateKeyPairSync("ed25519");
      const store = new InMemorySecurityStore();
      store.addDevice(
        "watch",
        publicKey.export({ type: "spki", format: "pem" }).toString(),
      );
      const body = Buffer.from([1, 2, 3]);
      const path = "/v1/transcribe?durationMs=1000";
      const timestamp = Date.now();
      const nonce = "transcription-route-nonce";
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
      const handler = createRequestHandler({
        store,
        adapter: {
          listTasks: async () => ({ data: [], nextCursor: null }),
          readTask: async () => ({}),
          listModels: async () => [],
          approvals: () => [],
          questions: () => [],
        },
        workspacePolicy: new WorkspacePolicy([]),
        transcriber: {
          async transcribe() {
            return "signed transcript";
          },
        },
        transcriptionTemporaryDirectory: directory,
      });

      const response = await handler(
        new Request(`http://localhost${path}`, {
          method: "POST",
          headers: {
            "content-type": "audio/mp4",
            "idempotency-key": "transcription-upload-0001",
            "x-relay-device": "watch",
            "x-relay-timestamp": String(timestamp),
            "x-relay-nonce": nonce,
            "x-relay-signature": signature,
          },
          body,
        }),
      );

      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), { transcript: "signed transcript" });
      assert.deepEqual(await readdir(directory), []);
    });
  });
});

async function withTemporaryDirectory(
  operation: (directory: string) => Promise<void>,
) {
  const directory = await mkdtemp(join(tmpdir(), "relay-transcription-test-"));
  try {
    await operation(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}
