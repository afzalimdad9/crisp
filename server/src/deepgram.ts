import { env } from "./env.js";

/// A transcribed word in the audio's timebase. Mirrors the fields the macOS app
/// needs (`text`, `start`, `end`, `confidence` → `Word.probability`).
export interface CloudWord {
  text: string;
  start: number;
  end: number;
  confidence: number;
}

export interface TranscribeResult {
  words: CloudWord[];
  provider: string;
}

/// Transcribes audio bytes into word-timestamped text. Uses Deepgram when
/// `DEEPGRAM_API_KEY` is set; otherwise returns a deterministic mock so the
/// service is fully runnable in local dev without a key.
export async function transcribeAudio(audio: Uint8Array, contentType: string): Promise<TranscribeResult> {
  if (!env.DEEPGRAM_API_KEY) {
    return { words: mockWords(), provider: "mock" };
  }

  const url =
    "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&punctuate=true&utterances=false";
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Token ${env.DEEPGRAM_API_KEY}`,
      "Content-Type": contentType || "audio/m4a",
    },
    // Node's fetch (undici) accepts a Uint8Array body at runtime; the cast works
    // around TS 5.7's generic ArrayBuffer typing of BodyInit.
    body: audio as unknown as BodyInit,
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`Deepgram error ${res.status}: ${detail.slice(0, 300)}`);
  }

  const json = (await res.json()) as DeepgramResponse;
  const dgWords = json.results?.channels?.[0]?.alternatives?.[0]?.words ?? [];
  const words: CloudWord[] = dgWords.map((w) => ({
    text: (w.punctuated_word ?? w.word).trim(),
    start: w.start,
    end: w.end,
    confidence: w.confidence ?? 1,
  }));
  return { words, provider: "deepgram" };
}

// Shape of the slice of Deepgram's response we read.
interface DeepgramResponse {
  results?: {
    channels?: {
      alternatives?: {
        words?: { word: string; punctuated_word?: string; start: number; end: number; confidence?: number }[];
      }[];
    }[];
  };
}

/// Deterministic fake transcript for local dev (no API key required).
function mockWords(): CloudWord[] {
  const sentence = "this is a mock cloud transcription used for local development";
  let t = 0;
  return sentence.split(" ").map((text) => {
    const start = t;
    const end = t + 0.35;
    t = end + 0.05;
    return { text, start, end, confidence: 0.99 };
  });
}
