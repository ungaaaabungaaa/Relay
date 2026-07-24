import type { RelayApproval, RelayModel, RelayQuestion, RelayTask } from "../domain.ts";
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
