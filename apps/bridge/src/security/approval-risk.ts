export type ApprovalRiskInput = {
  kind: "command" | "file" | "permission";
  command: string | null;
  reason: string | null;
};

export type ApprovalRisk = "normal" | "dangerous";

export type ApprovalRiskResult = {
  risk: ApprovalRisk;
  riskReasons: string[];
};

export function classifyApprovalRisk(
  input: ApprovalRiskInput,
): ApprovalRiskResult {
  const text = `${input.command ?? ""}\n${input.reason ?? ""}`.trim();
  const riskReasons: string[] = [];

  if (input.kind !== "command") {
    riskReasons.push(`${input.kind} approval`);
  }
  if (!text) {
    riskReasons.push("incomplete approval details");
  }
  if (/\b(sudo|doas|su)\b/i.test(text)) {
    riskReasons.push("privilege escalation");
  }
  if (/\b(rm|rmdir|dd|mkfs|diskutil)\b/i.test(text)) {
    riskReasons.push("destructive filesystem operation");
  }
  if (/\bgit\s+push\b|\b(npm|pnpm)\s+publish\b/i.test(text)) {
    riskReasons.push("remote write");
  }
  if (/[|;]|&&|\|\||>>?|<</.test(text)) {
    riskReasons.push("compound shell operation");
  }

  return riskReasons.length
    ? { risk: "dangerous", riskReasons }
    : { risk: "normal", riskReasons: [] };
}
