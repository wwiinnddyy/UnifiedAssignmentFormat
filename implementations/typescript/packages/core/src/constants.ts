export const UAF_PAYLOAD_FILENAME = "uaf_payload.csv" as const;

export const UAF_WATERMARK_TEXT = "本文件符合UAF标准规范" as const;

export const CSV_HEADER = "subject,date,content,tags" as const;

export const FIELD_NAMES = ["subject", "date", "content", "tags"] as const;

export const LIMITS = {
  subjectMax: 200,
  contentMax: 2000,
  tagMax: 50,
  tagCountMax: 20,
} as const;
