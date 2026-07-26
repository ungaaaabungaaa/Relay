import type {
  RelayActivityEntry,
  RelayApproval,
  RelayModel,
  RelayQuestion,
  RelayTask,
  RelayTaskDetail,
} from "../domain.ts";
import { classifyApprovalRisk } from "../security/approval-risk.ts";

type ProtocolThread = {
  id: string;
  name: string | null;
  preview: string;
  cwd: string;
  updatedAt: number;
  status: { type: string };
};

export function mapThread(thread: ProtocolThread): RelayTask {
  const status =
    thread.status.type === "active"
      ? "running"
      : thread.status.type === "systemError"
        ? "error"
        : "idle";
  return {
    id: thread.id,
    title: thread.name?.trim() || thread.preview.trim() || "Untitled task",
    preview: thread.preview,
    cwd: thread.cwd,
    updatedAt: thread.updatedAt,
    status,
  };
}

type ProtocolThreadItem = {
  id?: unknown;
  type?: unknown;
  [key: string]: unknown;
};

type ProtocolTurn = {
  id: string;
  status: string;
  startedAt: number | null;
  completedAt: number | null;
  items: ProtocolThreadItem[];
};

type ProtocolThreadDetail = {
  thread: ProtocolThread & { turns: ProtocolTurn[] };
};

export function mapThreadDetail(response: ProtocolThreadDetail): RelayTaskDetail {
  const { thread } = response;
  const activity = thread.turns
    .flatMap((turn) => turn.items.flatMap((item) => mapActivityEntry(turn, item)))
    .slice(-50);
  const activeTurn = thread.turns.findLast((turn) => turn.status === "inProgress");
  return {
    ...mapThread(thread),
    activeTurnId: activeTurn?.id ?? null,
    activity,
  };
}

function mapActivityEntry(
  turn: ProtocolTurn,
  item: ProtocolThreadItem,
): RelayActivityEntry[] {
  if (typeof item.id !== "string" || typeof item.type !== "string") return [];
  const base = {
    id: item.id,
    turnId: turn.id,
    status: activityStatus(item.status ?? turn.status),
    occurredAt: turn.startedAt,
  };
  switch (item.type) {
    case "userMessage": {
      const content = Array.isArray(item.content)
        ? item.content
            .filter(
              (entry): entry is { type: "text"; text: string } =>
                isRecord(entry) && entry.type === "text" && typeof entry.text === "string",
            )
            .map((entry) => entry.text)
            .join("\n")
        : "";
      return [{ ...base, kind: "user", title: "You", detail: content || null }];
    }
    case "agentMessage":
      return [
        {
          ...base,
          kind: "assistant",
          title: "Assistant",
          detail: typeof item.text === "string" && item.text ? item.text : null,
        },
      ];
    case "commandExecution":
      return [
        {
          ...base,
          kind: "command",
          title: typeof item.command === "string" ? item.command : "Command",
          detail: null,
        },
      ];
    case "fileChange": {
      const paths = Array.isArray(item.changes)
        ? item.changes
            .filter((change): change is { path: string } => isRecord(change) && typeof change.path === "string")
            .map((change) => change.path)
            .join("\n")
        : "";
      return [{ ...base, kind: "file", title: "File changes", detail: paths || null }];
    }
    case "mcpToolCall":
      return [
        {
          ...base,
          kind: "tool",
          title: toolTitle(item.server, item.tool),
          detail: null,
        },
      ];
    case "dynamicToolCall":
      return [
        {
          ...base,
          kind: "tool",
          title: toolTitle(item.namespace, item.tool),
          detail: null,
        },
      ];
    case "collabAgentToolCall":
      return [
        {
          ...base,
          kind: "tool",
          title: typeof item.tool === "string" ? item.tool : "Agent tool",
          detail: null,
        },
      ];
    default:
      return [{ ...base, kind: "status", title: statusTitle(item.type), detail: null }];
  }
}

function activityStatus(value: unknown): RelayActivityEntry["status"] {
  switch (value) {
    case "inProgress":
      return "running";
    case "completed":
      return "succeeded";
    case "failed":
    case "declined":
      return "failed";
    default:
      return "unknown";
  }
}

function toolTitle(namespace: unknown, tool: unknown): string {
  if (typeof namespace === "string" && typeof tool === "string") return `${namespace}/${tool}`;
  if (typeof tool === "string") return tool;
  return "Tool";
}

function statusTitle(type: string): string {
  return type === "plan" ? "Plan updated" : type === "reasoning" ? "Reasoning updated" : "Status update";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

type ApprovalRequest = {
  method:
    | "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval"
    | "item/permissions/requestApproval";
  params: {
    threadId: string;
    turnId: string;
    itemId: string;
    startedAtMs: number;
    command?: string | null;
    cwd?: string | null;
    reason?: string | null;
  };
};

export function mapApproval(id: string, request: ApprovalRequest): RelayApproval {
  const kind = request.method.includes("commandExecution")
    ? "command"
    : request.method.includes("fileChange")
      ? "file"
      : "permission";
  const risk = classifyApprovalRisk({
    kind,
    command: request.params.command ?? null,
    reason: request.params.reason ?? null,
  });
  return {
    id,
    threadId: request.params.threadId,
    turnId: request.params.turnId,
    itemId: request.params.itemId,
    kind,
    ...risk,
    command: request.params.command ?? null,
    cwd: request.params.cwd ?? null,
    reason: request.params.reason ?? null,
    startedAtMs: request.params.startedAtMs,
  };
}

type ProtocolQuestion = {
  threadId: string;
  turnId: string;
  itemId: string;
  questions: Array<{
    id: string;
    header: string;
    question: string;
    options: Array<{ label: string; description: string }> | null;
  }>;
};

export function mapQuestion(id: string, params: ProtocolQuestion): RelayQuestion {
  return {
    id,
    threadId: params.threadId,
    turnId: params.turnId,
    itemId: params.itemId,
    questions: params.questions.map((question) => ({
      id: question.id,
      header: question.header,
      question: question.question,
      options: question.options ?? [],
    })),
  };
}

type ProtocolModel = {
  id: string;
  displayName: string;
  description: string;
  supportedReasoningEfforts: Array<{ reasoningEffort: string }>;
  defaultReasoningEffort: string;
  isDefault: boolean;
};

export function mapModel(model: ProtocolModel): RelayModel {
  return {
    id: model.id,
    name: model.displayName,
    description: model.description,
    efforts: model.supportedReasoningEfforts.map((option) => option.reasoningEffort),
    defaultEffort: model.defaultReasoningEffort,
    isDefault: model.isDefault,
  };
}
