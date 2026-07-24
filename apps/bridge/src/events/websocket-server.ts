import type { IncomingMessage, Server } from "node:http";
import type { Duplex } from "node:stream";
import WebSocket, { WebSocketServer } from "ws";
import { verifyRequest } from "../security/authentication.ts";
import type { SecurityStore } from "../security/store.ts";
import type { EventHub, RelayEvent } from "./event-hub.ts";

type EventWebSocketOptions = {
  store: SecurityStore;
  eventHub: EventHub;
  sessionDurationMs?: number;
};

export function attachEventWebSocket(
  server: Server,
  options: EventWebSocketOptions,
): void {
  const sockets = new WebSocketServer({ noServer: true });
  const closeServer = server.close.bind(server);

  server.close = ((callback?: (error?: Error) => void) => {
    for (const client of sockets.clients) client.terminate();
    sockets.close();
    return closeServer(callback);
  }) as Server["close"];

  server.on("upgrade", (request, socket, head) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method !== "GET" || url.pathname !== "/v1/events") {
      rejectUpgrade(socket, 404, "Not Found");
      return;
    }
    const afterValue = url.searchParams.get("after");
    if (!afterValue || !/^\d+$/.test(afterValue)) {
      rejectUpgrade(socket, 400, "Bad Request");
      return;
    }
    const after = Number(afterValue);
    if (!Number.isSafeInteger(after)) {
      rejectUpgrade(socket, 400, "Bad Request");
      return;
    }

    try {
      verifyRequest(options.store, {
        deviceId: requestHeader(request, "x-relay-device"),
        method: "GET",
        path: `${url.pathname}${url.search}`,
        body: new Uint8Array(),
        timestamp: Number(requestHeader(request, "x-relay-timestamp")),
        nonce: requestHeader(request, "x-relay-nonce"),
        signature: requestHeader(request, "x-relay-signature"),
      });
    } catch {
      rejectUpgrade(socket, 401, "Unauthorized");
      return;
    }

    sockets.handleUpgrade(request, socket, head, (client) => {
      streamEvents(
        client,
        options.eventHub,
        after,
        options.sessionDurationMs ?? 15 * 60_000,
      );
    });
  });
}

function streamEvents(
  socket: WebSocket,
  eventHub: EventHub,
  after: number,
  sessionDurationMs: number,
): void {
  const resume = eventHub.resumeAfter(after);
  if (resume.snapshotRequired) {
    socket.send(
      JSON.stringify({
        type: "snapshot.required",
        after,
        latestEventId: eventHub.latestEventId,
      }),
      () => socket.close(1000, "snapshot required"),
    );
    return;
  }

  const send = (event: RelayEvent) => {
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(event));
    }
  };
  const unsubscribe = eventHub.subscribe(send);
  for (const event of resume.events) send(event);

  const sessionTimer = setTimeout(() => {
    socket.close(1000, "session expired");
  }, sessionDurationMs);
  sessionTimer.unref();

  socket.once("close", () => {
    clearTimeout(sessionTimer);
    unsubscribe();
  });
}

function requestHeader(request: IncomingMessage, name: string): string {
  const value = request.headers[name];
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function rejectUpgrade(socket: Duplex, status: number, reason: string): void {
  socket.end(
    `HTTP/1.1 ${status} ${reason}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`,
  );
}
