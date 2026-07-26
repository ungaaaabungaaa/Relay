import type { RelayApproval, RelayModel, RelayQuestion } from "./domain.ts";

type ObjectBody = Record<string, unknown>;

export function validateApprovalDecision(
  approval: RelayApproval,
  body: unknown,
): { decision: "approve" | "deny" } {
  const input = asObject(body, "invalid approval decision");
  if (input.decision !== "approve" && input.decision !== "deny") {
    throw new Error("invalid approval decision");
  }
  if (
    input.decision === "approve" &&
    approval.risk === "dangerous" &&
    input.dangerousConfirmation !== true
  ) {
    throw new Error("dangerous confirmation required");
  }
  return { decision: input.decision };
}

export function validateQuestionAnswers(
  question: RelayQuestion,
  body: unknown,
): Record<string, string[]> {
  const input = asObject(body, "invalid question answers");
  const answers = asObject(input.answers, "invalid question answers");
  const expectedQuestions = new Map(
    question.questions.map((item) => [item.id, item.options.map((option) => option.label)]),
  );
  const answerEntries = Object.entries(answers);

  if (answerEntries.length !== expectedQuestions.size) {
    throw new Error("answers required for every question");
  }

  const validated: Record<string, string[]> = {};
  for (const [questionId, selected] of answerEntries) {
    const options = expectedQuestions.get(questionId);
    if (!options) throw new Error("unknown question");
    if (!Array.isArray(selected) || selected.length === 0) {
      throw new Error("answer required");
    }
    if (!selected.every((answer): answer is string => typeof answer === "string")) {
      throw new Error("invalid question answer");
    }
    if (!selected.every((answer) => options.includes(answer))) {
      throw new Error("unknown option");
    }
    validated[questionId] = [...selected];
  }
  return validated;
}

export function validateNewTaskInput(
  body: unknown,
  models: RelayModel[],
): { cwd: string; model: string; effort: string; prompt: string } {
  const input = asObject(body, "invalid task input");
  const cwd = nonEmptyString(input.cwd, "invalid task input");
  const model = nonEmptyString(input.model, "invalid task input");
  const effort = nonEmptyString(input.effort, "invalid task input");
  const prompt = nonEmptyString(input.prompt, "invalid task input");
  const selectedModel = models.find((candidate) => candidate.id === model);
  if (!selectedModel) throw new Error("unknown model");
  if (!selectedModel.efforts.includes(effort)) throw new Error("unknown effort");
  return { cwd, model, effort, prompt };
}

export function validateInstructionInput(body: unknown): { text: string } {
  const input = asObject(body, "invalid instruction");
  return { text: nonEmptyString(input.text, "invalid instruction") };
}

export function validateSteerInput(body: unknown): { turnId: string; text: string } {
  const input = asObject(body, "invalid steer request");
  return {
    turnId: nonEmptyString(input.turnId, "invalid steer request"),
    text: nonEmptyString(input.text, "invalid steer request"),
  };
}

export function validateStopInput(body: unknown): { turnId: string } {
  const input = asObject(body, "invalid stop request");
  return { turnId: nonEmptyString(input.turnId, "invalid stop request") };
}

function asObject(value: unknown, message: string): ObjectBody {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(message);
  }
  return value as ObjectBody;
}

function nonEmptyString(value: unknown, message: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(message);
  return value;
}
