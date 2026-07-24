export type RelayTask = {
  id: string;
  title: string;
  preview: string;
  cwd: string;
  updatedAt: number;
  status: "idle" | "running" | "error" | "offline";
};

export type RelayApproval = {
  id: string;
  threadId: string;
  turnId: string;
  itemId: string;
  kind: "command" | "file" | "permission";
  command: string | null;
  cwd: string | null;
  reason: string | null;
  startedAtMs: number;
};

export type RelayQuestion = {
  id: string;
  threadId: string;
  turnId: string;
  itemId: string;
  questions: Array<{
    id: string;
    header: string;
    question: string;
    options: Array<{ label: string; description: string }>;
  }>;
};

export type RelayModel = {
  id: string;
  name: string;
  description: string;
  efforts: string[];
  defaultEffort: string;
  isDefault: boolean;
};
