import { mkdir, rm, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { join } from "node:path";

export interface Transcriber {
  transcribe(filePath: string): Promise<string>;
}

type TranscribeAudioOptions = {
  audio: Uint8Array;
  contentType: string;
  durationMs: number;
  temporaryDirectory: string;
  transcriber: Transcriber;
  timeoutMs?: number;
};

const MAX_AUDIO_BYTES = 2 * 1024 * 1024;
const MAX_AUDIO_DURATION_MS = 30_000;
const ALLOWED_AUDIO_TYPES = new Set([
  "audio/aac",
  "audio/mp4",
  "audio/m4a",
  "audio/mpeg",
  "audio/ogg",
  "audio/wav",
  "audio/webm",
]);

export async function transcribeAudio(
  options: TranscribeAudioOptions,
): Promise<string> {
  const contentType = options.contentType.split(";", 1)[0]?.trim().toLowerCase();
  if (!contentType || !ALLOWED_AUDIO_TYPES.has(contentType)) {
    throw new Error("unsupported audio type");
  }
  if (
    !Number.isSafeInteger(options.durationMs) ||
    options.durationMs <= 0 ||
    options.durationMs > MAX_AUDIO_DURATION_MS
  ) {
    throw new Error("audio duration exceeds 30 seconds");
  }
  if (options.audio.byteLength === 0) throw new Error("audio is empty");
  if (options.audio.byteLength > MAX_AUDIO_BYTES) {
    throw new Error("audio exceeds 2 MiB");
  }

  await mkdir(options.temporaryDirectory, { recursive: true, mode: 0o700 });
  const filePath = join(
    options.temporaryDirectory,
    `relay-audio-${randomUUID()}.m4a`,
  );
  await writeFile(filePath, options.audio, { flag: "wx", mode: 0o600 });
  try {
    const transcript = await withTimeout(
      options.transcriber.transcribe(filePath),
      options.timeoutMs ?? 30_000,
    );
    if (!transcript.trim()) throw new Error("transcription was empty");
    return transcript.trim();
  } finally {
    await rm(filePath, { force: true });
  }
}

async function withTimeout<T>(operation: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<T>((_resolve, reject) => {
        timer = setTimeout(
          () => reject(new Error("transcription timed out")),
          timeoutMs,
        );
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}
