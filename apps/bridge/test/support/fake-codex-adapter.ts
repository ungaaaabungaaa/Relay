import type {
  RelayApproval,
  RelayModel,
  RelayQuestion,
  RelayTask,
  RelayTaskDetail,
} from "../../src/domain.ts";

export type FakeCodexCall = {
  operation:
    | "listTasks"
    | "readTask"
    | "listModels"
    | "answerApproval"
    | "answerQuestion"
    | "startTask"
    | "sendInstruction"
    | "steerTask"
    | "stopTask";
  arguments: unknown[];
};

export class FakeCodexAdapter {
  task: RelayTask = {
    id: "task-1",
    title: "Build Relay",
    preview: "Implement the encrypted Apple client",
    cwd: "/workspace",
    updatedAt: 1_000,
    status: "running",
  };

  readonly taskDetail: RelayTaskDetail = {
    ...this.task,
    activeTurnId: "turn-1",
    activity: [
      {
        id: "activity-1",
        turnId: "turn-1",
        kind: "assistant",
        title: "Implementing the encrypted transport",
        detail: null,
        status: "running",
        occurredAt: 1_000,
      },
    ],
  };

  readonly model: RelayModel = {
    id: "gpt-5",
    name: "GPT-5",
    description: "Relay test model",
    efforts: ["medium", "high"],
    defaultEffort: "medium",
    isDefault: true,
  };

  readonly approval: RelayApproval = {
    id: "approval-1",
    threadId: "task-1",
    turnId: "turn-1",
    itemId: "item-1",
    kind: "command",
    risk: "normal",
    riskReasons: [],
    command: "pnpm test",
    cwd: "/workspace",
    reason: null,
    startedAtMs: 1_000,
  };

  readonly question: RelayQuestion = {
    id: "question-1",
    threadId: "task-1",
    turnId: "turn-1",
    itemId: "item-2",
    questions: [
      {
        id: "release-channel",
        header: "Release",
        question: "Choose a release channel",
        options: [
          { label: "Beta", description: "Use the beta channel" },
          { label: "Stable", description: "Use the stable channel" },
        ],
      },
    ],
  };

  readonly calls: FakeCodexCall[] = [];
  onCall: (call: FakeCodexCall) => void = () => {};
  #approvals: RelayApproval[] = [this.approval];
  #questions: RelayQuestion[] = [this.question];

  async listTasks(cursor: string | null = null) {
    this.#record("listTasks", cursor);
    return { data: [structuredClone(this.task)], nextCursor: null };
  }

  async readTask(threadId: string) {
    this.#record("readTask", threadId);
    return structuredClone(this.taskDetail);
  }

  async listModels() {
    this.#record("listModels");
    return [structuredClone(this.model)];
  }

  approvals() {
    return structuredClone(this.#approvals);
  }

  questions() {
    return structuredClone(this.#questions);
  }

  answerApproval(id: string, approved: boolean) {
    this.#record("answerApproval", id, approved);
    this.#approvals = this.#approvals.filter((approval) => approval.id !== id);
  }

  answerQuestion(id: string, answers: Record<string, string[]>) {
    this.#record("answerQuestion", id, structuredClone(answers));
    this.#questions = this.#questions.filter((question) => question.id !== id);
  }

  async startTask(input: {
    cwd: string;
    model: string;
    effort: string;
    prompt: string;
  }) {
    this.#record("startTask", structuredClone(input));
    return { thread: { id: "task-created" } };
  }

  async sendInstruction(threadId: string, text: string) {
    this.#record("sendInstruction", threadId, text);
    return { turn: { id: "turn-instruction" } };
  }

  async steerTask(threadId: string, turnId: string, text: string) {
    this.#record("steerTask", threadId, turnId, text);
    return { turnId };
  }

  async stopTask(threadId: string, turnId: string) {
    this.#record("stopTask", threadId, turnId);
  }

  #record(operation: FakeCodexCall["operation"], ...args: unknown[]): void {
    const call = { operation, arguments: args };
    this.calls.push(call);
    this.onCall(call);
  }
}
