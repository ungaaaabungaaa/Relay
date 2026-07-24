import type { RelayApproval, RelayModel, RelayQuestion, RelayTask } from "../domain.ts";
import { EventHub } from "../events/event-hub.ts";
import { CodexRpcClient, type RpcServerRequest } from "./client.ts";
import { mapApproval, mapModel, mapQuestion, mapThread } from "./mappers.ts";

type PendingAction =
  | { request: RpcServerRequest; value: RelayApproval }
  | { request: RpcServerRequest; value: RelayQuestion };

export class CodexAdapter {
  readonly events: EventHub;
  private readonly pending = new Map<string, PendingAction>();
  private readonly client: CodexRpcClient;

  constructor(
    client = new CodexRpcClient(),
    events = new EventHub(),
  ) {
    this.client = client;
    this.events = events;
    this.client.onNotification((method, params) => {
      this.events.publish(method, params);
    });
    this.client.onRequest((request) => this.captureRequest(request));
  }

  start() {
    return this.client.start();
  }

  stop() {
    this.client.stop();
  }

  async listTasks(cursor: string | null = null): Promise<{
    data: RelayTask[];
    nextCursor: string | null;
  }> {
    const response = (await this.client.request("thread/list", {
      cursor,
      limit: 50,
      sortKey: "updated_at",
      sortDirection: "desc",
    })) as { data: Parameters<typeof mapThread>[0][]; nextCursor: string | null };
    return { data: response.data.map(mapThread), nextCursor: response.nextCursor };
  }

  async readTask(threadId: string) {
    return this.client.request("thread/read", { threadId, includeTurns: true });
  }

  async listModels(): Promise<RelayModel[]> {
    const response = (await this.client.request("model/list", {
      limit: 100,
      includeHidden: false,
    })) as { data: Parameters<typeof mapModel>[0][] };
    return response.data.map(mapModel);
  }

  async startTask(input: {
    cwd: string;
    model: string;
    effort: string;
    prompt: string;
  }) {
    const started = (await this.client.request("thread/start", {
      cwd: input.cwd,
      model: input.model,
      approvalPolicy: "on-request",
    })) as { thread: { id: string } };
    await this.sendInstruction(started.thread.id, input.prompt, {
      model: input.model,
      effort: input.effort,
    });
    return started;
  }

  sendInstruction(
    threadId: string,
    text: string,
    overrides: { model?: string; effort?: string } = {},
  ) {
    return this.client.request("turn/start", {
      threadId,
      input: [{ type: "text", text, text_elements: [] }],
      ...overrides,
    });
  }

  steerTask(threadId: string, turnId: string, text: string) {
    return this.client.request("turn/steer", {
      threadId,
      expectedTurnId: turnId,
      input: [{ type: "text", text, text_elements: [] }],
    });
  }

  stopTask(threadId: string, turnId: string) {
    return this.client.request("turn/interrupt", { threadId, turnId });
  }

  approvals() {
    return [...this.pending.values()]
      .map((pending) => pending.value)
      .filter((value): value is RelayApproval => "kind" in value);
  }

  questions() {
    return [...this.pending.values()]
      .map((pending) => pending.value)
      .filter((value): value is RelayQuestion => "questions" in value);
  }

  answerApproval(id: string, approve: boolean) {
    const pending = this.pending.get(id);
    if (!pending || !("kind" in pending.value)) throw new Error("expired approval");
    const { request, value } = pending;
    if (value.kind === "permission") {
      const requested = request.params.permissions as {
        network?: unknown;
        fileSystem?: unknown;
      };
      this.client.respond(request.id, {
        permissions: approve
          ? {
              ...(requested.network ? { network: requested.network } : {}),
              ...(requested.fileSystem ? { fileSystem: requested.fileSystem } : {}),
            }
          : {},
        scope: "turn",
      });
    } else {
      this.client.respond(request.id, { decision: approve ? "accept" : "decline" });
    }
    this.pending.delete(id);
  }

  answerQuestion(id: string, answers: Record<string, string[]>) {
    const pending = this.pending.get(id);
    if (!pending || !("questions" in pending.value)) throw new Error("expired question");
    this.client.respond(pending.request.id, {
      answers: Object.fromEntries(
        Object.entries(answers).map(([questionId, selectedAnswers]) => [
          questionId,
          { answers: selectedAnswers },
        ]),
      ),
    });
    this.pending.delete(id);
  }

  private captureRequest(request: RpcServerRequest) {
    const id = String(request.id);
    if (
      request.method === "item/commandExecution/requestApproval" ||
      request.method === "item/fileChange/requestApproval" ||
      request.method === "item/permissions/requestApproval"
    ) {
      const value = mapApproval(id, request as Parameters<typeof mapApproval>[1]);
      this.pending.set(id, { request, value });
      this.events.publish("approval.requested", value);
    } else if (request.method === "item/tool/requestUserInput") {
      const value = mapQuestion(
        id,
        request.params as Parameters<typeof mapQuestion>[1],
      );
      this.pending.set(id, { request, value });
      this.events.publish("question.requested", value);
    }
  }
}
