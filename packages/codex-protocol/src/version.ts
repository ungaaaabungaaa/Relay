export type CodexVersion = {
  raw: string;
  semver: string;
};

export function readCodexVersion(output: string): CodexVersion {
  const raw = output.trim();
  const match = raw.match(/\b(\d+\.\d+\.\d+)\b/);
  if (!match?.[1]) {
    throw new Error(`Unsupported Codex version output: ${raw}`);
  }
  return { raw, semver: match[1] };
}
