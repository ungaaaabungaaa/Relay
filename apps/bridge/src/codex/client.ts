import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";

type JsonRpcId = number | string;
type JsonObject = Record<string, unknown>;

export type RpcServerRequest = {
  id: JsonRpcId;
  method: string;
  params: JsonObject;
};

export class CodexRpcClient {
  private process: ChildProcessWithoutNullStreams | null = null;
  private nextId = 1;
  private pending = new Map<
    JsonRpcId,
    { resolve: (value: unknown) => void; reject: (error: Error) => void }
  >();
  private notificationHandlers = new Set<(method: string, params: JsonObject) => void>();
  private requestHandlers = new Set<(request: RpcServerRequest) => void>();

  async start() {
    if (this.process) return;
    const child = spawn("codex", ["app-server", "--stdio"], {
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.process = child;
    const fail = (error: Error) => {
      if (this.process !== child) return;
      for (const pending of this.pending.values()) {
        pending.reject(error);
      }
      this.pending.clear();
      this.process = null;
    };
    child.on("error", (error: NodeJS.ErrnoException) => {
      fail(
        new Error(
          `Codex app-server could not start (${error.code ?? "UNKNOWN"})`,
        ),
      );
    });
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => this.onLine(line));
    child.on("exit", () => {
      fail(new Error("Codex app-server exited"));
    });
    await this.request("initialize", {
      clientInfo: { name: "relay", title: "Relay Watch Bridge", version: "0.1.0" },
      capabilities: {
        experimentalApi: true,
        requestAttestation: false,
      },
    });
    this.notify("initialized");
  }

  async request(method: string, params?: JsonObject): Promise<unknown> {
    if (!this.process) throw new Error("Codex app-server is not running");
    const id = this.nextId++;
    const result = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.write({ id, method, ...(params === undefined ? {} : { params }) });
    return result;
  }

  respond(id: JsonRpcId, result: unknown) {
    this.write({ id, result });
  }

  notify(method: string, params?: JsonObject) {
    this.write({ method, ...(params === undefined ? {} : { params }) });
  }

  onNotification(handler: (method: string, params: JsonObject) => void) {
    this.notificationHandlers.add(handler);
    return () => this.notificationHandlers.delete(handler);
  }

  onRequest(handler: (request: RpcServerRequest) => void) {
    this.requestHandlers.add(handler);
    return () => this.requestHandlers.delete(handler);
  }

  stop() {
    this.process?.kill("SIGTERM");
  }

  private write(message: unknown) {
    if (!this.process) throw new Error("Codex app-server is not running");
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private onLine(line: string) {
    let message: JsonObject;
    try {
      message = JSON.parse(line) as JsonObject;
    } catch {
      return;
    }
    if ("id" in message && ("result" in message || "error" in message)) {
      const pending = this.pending.get(message.id as JsonRpcId);
      if (!pending) return;
      this.pending.delete(message.id as JsonRpcId);
      if (message.error) {
        pending.reject(new Error(JSON.stringify(message.error)));
      } else {
        pending.resolve(message.result);
      }
      return;
    }
    if ("id" in message && typeof message.method === "string") {
      for (const handler of this.requestHandlers) {
        handler({
          id: message.id as JsonRpcId,
          method: message.method,
          params: (message.params ?? {}) as JsonObject,
        });
      }
      return;
    }
    if (typeof message.method === "string") {
      for (const handler of this.notificationHandlers) {
        handler(message.method, (message.params ?? {}) as JsonObject);
      }
    }
  }
}
