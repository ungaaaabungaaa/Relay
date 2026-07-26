import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import {
  ActionExecutor,
  ActionInProgressError,
  ActionPreviouslyFailedError,
  IdempotencyConflictError,
} from "./actions/action-executor.ts";
import type { CodexAdapter } from "./codex/adapter.ts";
import type { EventHub } from "./events/event-hub.ts";
import { attachEventWebSocket } from "./events/websocket-server.ts";
import { verifyRequest } from "./security/authentication.ts";
import { PairingService } from "./security/pairing.ts";
import type { PairingSessionService } from "./security/pairing-session.ts";
import type { SecurityStore } from "./security/store.ts";
import {
  WorkspacePolicyError,
  type WorkspacePolicy,
} from "./workspaces/workspace-policy.ts";
import type { Transcriber } from "./transcription/transcriber.ts";
import { transcribeAudio } from "./transcription/transcriber.ts";
import {
  validateApprovalDecision,
  validateInstructionInput,
  validateNewTaskInput,
  validateQuestionAnswers,
  validateSteerInput,
  validateStopInput,
} from "./watch-request-validation.ts";

type Adapter = Pick<
  CodexAdapter,
  | "listTasks"
  | "readTask"
  | "listModels"
  | "approvals"
  | "questions"
  | "answerApproval"
  | "answerQuestion"
  | "sendInstruction"
  | "steerTask"
  | "stopTask"
  | "startTask"
>;

type HandlerOptions = {
  store: SecurityStore;
  pairingSessions?: PairingSessionService;
  pairingSource?: (request: Request) => string;
  adapter: Partial<Adapter> & Pick<Adapter, "listTasks" | "readTask" | "listModels" | "approvals" | "questions">;
  workspacePolicy: WorkspacePolicy;
  transcriber?: Transcriber;
  transcriptionTemporaryDirectory?: string;
  transcriptionTimeoutMs?: number;
};

type RelayServerOptions = HandlerOptions & {
  eventHub: EventHub;
};

const json = (body: unknown, status = 200) =>
  Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });

async function parseJson(request: Request) {
  if (!request.body) return {};
  const text = await request.text();
  if (!text) return {};
  if (text.length > 1_000_000) throw new Error("body too large");
  return JSON.parse(text) as Record<string, unknown>;
}

export function createRequestHandler(options: HandlerOptions) {
  const pairing = new PairingService(options.store);
  const actions = new ActionExecutor(options.store);
  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "relay" });
    }
    const pairingStatus = url.pathname.match(
      /^\/v1\/pairing-sessions\/([a-f0-9]{32})\/status$/,
    );
    if (
      request.method === "GET" &&
      pairingStatus?.[1] &&
      options.pairingSessions
    ) {
      try {
        return json(
          options.pairingSessions.poll(
            pairingStatus[1],
            url.searchParams.get("pollToken") ?? "",
          ),
        );
      } catch {
        return json({ error: "not found" }, 404);
      }
    }
    const pairingSession = url.pathname.match(
      /^\/v1\/pairing-sessions\/([a-f0-9]{32})$/,
    );
    if (pairingSession?.[1] && options.pairingSessions) {
      try {
        if (request.method === "GET") {
          return json(options.pairingSessions.discover(pairingSession[1]));
        }
        if (request.method === "POST") {
          const body = await parseJson(request);
          return json(
            options.pairingSessions.submit(
              pairingSession[1],
              options.pairingSource?.(request) ??
                request.headers.get("x-relay-source-internal") ??
                "unknown",
              body as never,
            ),
            202,
          );
        }
      } catch {
        return json({ error: "pairing failed" }, 401);
      }
    }
    if (url.pathname.startsWith("/v1/pairing-sessions/")) {
      return json({ error: "not found" }, 404);
    }
    if (request.method === "POST" && url.pathname === "/v1/pair") {
      try {
        const body = await parseJson(request);
        if (
          typeof body.code !== "string" ||
          typeof body.name !== "string" ||
          typeof body.publicKey !== "string"
        ) {
          return json({ error: "invalid request" }, 400);
        }
        const device = pairing.exchange(body.code, body.name, body.publicKey);
        return json({ deviceId: device.id });
      } catch {
        return json({ error: "pairing failed" }, 401);
      }
    }
    if (!url.pathname.startsWith("/v1/")) return json({ error: "not found" }, 404);

    const bodyBytes = new Uint8Array(await request.clone().arrayBuffer());
    let deviceId: string;
    try {
      deviceId = verifyRequest(options.store, {
        deviceId: request.headers.get("x-relay-device") ?? "",
        method: request.method,
        path: `${url.pathname}${url.search}`,
        body: bodyBytes,
        timestamp: Number(request.headers.get("x-relay-timestamp")),
        nonce: request.headers.get("x-relay-nonce") ?? "",
        signature: request.headers.get("x-relay-signature") ?? "",
      });
    } catch {
      return json({ error: "unauthorized" }, 401);
    }

    const idempotencyKey = request.headers.get("idempotency-key") ?? "";
    if (
      request.method === "POST" &&
      !/^[A-Za-z0-9._:-]{16,128}$/.test(idempotencyKey)
    ) {
      return json({ error: "invalid idempotency key" }, 400);
    }

    try {
      if (request.method === "GET" && url.pathname === "/v1/tasks") {
        return json(await options.adapter.listTasks(url.searchParams.get("cursor")));
      }
      const taskMatch = url.pathname.match(/^\/v1\/tasks\/([^/]+)$/);
      if (request.method === "GET" && taskMatch?.[1]) {
        return json(await options.adapter.readTask(taskMatch[1]));
      }
      if (request.method === "GET" && url.pathname === "/v1/models") {
        return json({ data: await options.adapter.listModels() });
      }
      if (request.method === "GET" && url.pathname === "/v1/inbox") {
        return json({
          approvals: options.adapter.approvals(),
          questions: options.adapter.questions(),
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/folders") {
        return json(
          await options.workspacePolicy.list(
            url.searchParams.get("path") ?? undefined,
          ),
        );
      }
      if (request.method === "POST" && url.pathname === "/v1/transcribe") {
        if (!options.transcriber || !options.transcriptionTemporaryDirectory) {
          return json({ error: "transcription unavailable" }, 503);
        }
        try {
          const transcript = await transcribeAudio({
            audio: bodyBytes,
            contentType: request.headers.get("content-type") ?? "",
            durationMs: Number(url.searchParams.get("durationMs")),
            temporaryDirectory: options.transcriptionTemporaryDirectory,
            transcriber: options.transcriber,
            timeoutMs: options.transcriptionTimeoutMs,
          });
          return json({ transcript });
        } catch (error) {
          const message =
            error instanceof Error ? error.message : "transcription failed";
          if (message.includes("timed out")) {
            return json({ error: "transcription timed out" }, 504);
          }
          if (
            message.includes("unsupported") ||
            message.includes("duration") ||
            message.includes("2 MiB") ||
            message.includes("empty")
          ) {
            return json({ error: message }, 400);
          }
          return json({ error: "transcription failed" }, 502);
        }
      }
      if (request.method === "POST") {
        const body = await parseJson(request);
        const approval = url.pathname.match(/^\/v1\/approvals\/([^/]+)$/);
        if (approval?.[1] && options.adapter.answerApproval) {
          const pending = options.adapter
            .approvals()
            .find((item) => item.id === approval[1]);
          if (!pending) throw new Error("expired approval");
          const decision = validateApprovalDecision(pending, body);
          const approve = decision.decision === "approve";
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: `approval.${approve ? "approve" : "deny"}.${pending?.risk ?? "dangerous"}`,
                target: approval[1],
              },
              () => {
                options.adapter.answerApproval?.(approval[1], approve);
                return { ok: true };
              },
            ),
          );
        }
        const question = url.pathname.match(/^\/v1\/questions\/([^/]+)$/);
        if (question?.[1] && options.adapter.answerQuestion) {
          const pending = options.adapter
            .questions()
            .find((item) => item.id === question[1]);
          if (!pending) throw new Error("expired question");
          const answers = validateQuestionAnswers(pending, body);
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: "question.answer",
                target: question[1],
              },
              () => {
                options.adapter.answerQuestion?.(
                  question[1],
                  answers,
                );
                return { ok: true };
              },
            ),
          );
        }
        if (url.pathname === "/v1/tasks" && options.adapter.startTask) {
          const input = validateNewTaskInput(
            body,
            await options.adapter.listModels(),
          );
          const cwd = await options.workspacePolicy.assertAllowed(input.cwd);
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: "task.start",
                target: "new-task",
              },
              async () => {
                const started = await options.adapter.startTask?.({
                  cwd,
                  model: input.model,
                  effort: input.effort,
                  prompt: input.prompt,
                });
                return { taskId: (started as { thread: { id: string } }).thread.id };
              },
            ),
            201,
          );
        }
        const instruction = url.pathname.match(/^\/v1\/tasks\/([^/]+)\/instructions$/);
        if (instruction?.[1] && options.adapter.sendInstruction) {
          const input = validateInstructionInput(body);
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: "task.instruction",
                target: instruction[1],
              },
              async () => {
                const started = await options.adapter.sendInstruction?.(
                  instruction[1],
                  input.text,
                );
                return { turnId: (started as { turn: { id: string } }).turn.id };
              },
            ),
          );
        }
        const steer = url.pathname.match(/^\/v1\/tasks\/([^/]+)\/steer$/);
        if (steer?.[1] && options.adapter.steerTask) {
          const input = validateSteerInput(body);
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: "task.steer",
                target: steer[1],
              },
              async () => {
                const steered = await options.adapter.steerTask?.(
                  steer[1],
                  input.turnId,
                  input.text,
                );
                return { turnId: (steered as { turnId: string }).turnId };
              },
            ),
          );
        }
        const stop = url.pathname.match(/^\/v1\/tasks\/([^/]+)\/stop$/);
        if (stop?.[1] && options.adapter.stopTask) {
          const input = validateStopInput(body);
          return json(
            await actions.run(
              {
                deviceId,
                idempotencyKey,
                action: "task.stop",
                target: stop[1],
              },
              async () => {
                await options.adapter.stopTask?.(stop[1], input.turnId);
                return { ok: true };
              },
            ),
          );
        }
      }
      return json({ error: "not found" }, 404);
    } catch (error) {
      if (error instanceof WorkspacePolicyError) {
        return json({ error: error.message }, 403);
      }
      if (
        error instanceof ActionInProgressError ||
        error instanceof ActionPreviouslyFailedError ||
        error instanceof IdempotencyConflictError
      ) {
        return json({ error: error.message }, 409);
      }
      const message = error instanceof Error ? error.message : "request failed";
      return json({ error: message }, message.includes("expired") ? 409 : 400);
    } finally {
      void deviceId;
    }
  };
}

async function nodeRequest(request: IncomingMessage, limit = 8_000_000) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) throw new Error("body too large");
    chunks.push(buffer);
  }
  const host = request.headers.host ?? "127.0.0.1";
  const headers = new Headers(request.headers as HeadersInit);
  headers.set(
    "x-relay-source-internal",
    request.socket.remoteAddress ?? "unknown",
  );
  return new Request(`http://${host}${request.url ?? "/"}`, {
    method: request.method,
    headers,
    ...(chunks.length ? { body: Buffer.concat(chunks), duplex: "half" } : {}),
  } as RequestInit);
}

async function sendNodeResponse(response: Response, target: ServerResponse) {
  target.statusCode = response.status;
  response.headers.forEach((value, name) => target.setHeader(name, value));
  target.end(Buffer.from(await response.arrayBuffer()));
}

export function createRelayServer(options: RelayServerOptions) {
  const handler = createRequestHandler(options);
  const server = createServer(async (request, response) => {
    try {
      await sendNodeResponse(await handler(await nodeRequest(request)), response);
    } catch {
      response.statusCode = 400;
      response.end(JSON.stringify({ error: "invalid request" }));
    }
  });
  attachEventWebSocket(server, {
    store: options.store,
    eventHub: options.eventHub,
  });
  return server;
}
