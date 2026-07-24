import { openAsBlob } from "node:fs";
import type { Transcriber } from "./transcriber.ts";

type OpenAITranscriberOptions = {
  apiKey: string;
  endpoint?: string;
  model?: string;
  fetchImplementation?: typeof fetch;
};

export class OpenAITranscriber implements Transcriber {
  private readonly apiKey: string;
  private readonly endpoint: string;
  private readonly model: string;
  private readonly fetchImplementation: typeof fetch;

  constructor(options: OpenAITranscriberOptions) {
    if (!options.apiKey.trim()) throw new Error("OpenAI API key is required");
    this.apiKey = options.apiKey;
    this.endpoint =
      options.endpoint ?? "https://api.openai.com/v1/audio/transcriptions";
    this.model = options.model ?? "gpt-4o-mini-transcribe";
    this.fetchImplementation = options.fetchImplementation ?? fetch;
  }

  async transcribe(filePath: string): Promise<string> {
    const form = new FormData();
    form.append("file", await openAsBlob(filePath, { type: "audio/mp4" }), "relay.m4a");
    form.append("model", this.model);
    form.append("response_format", "json");

    const response = await this.fetchImplementation(this.endpoint, {
      method: "POST",
      headers: { authorization: `Bearer ${this.apiKey}` },
      body: form,
    });
    if (!response.ok) {
      throw new Error(`transcription provider failed (${response.status})`);
    }
    const result = (await response.json()) as { text?: unknown };
    if (typeof result.text !== "string" || !result.text.trim()) {
      throw new Error("transcription provider returned no text");
    }
    return result.text.trim();
  }
}
