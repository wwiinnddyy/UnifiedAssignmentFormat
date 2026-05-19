export enum UafErrorCode {
  InvalidCsv = "INVALID_CSV",
  InvalidPayload = "INVALID_PAYLOAD",
  NoPayload = "NO_PAYLOAD",
  CorruptPdf = "CORRUPT_PDF",
}

export class UafError extends Error {
  constructor(
    public readonly code: UafErrorCode,
    message: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "UafError";
  }
}
