import { z } from "zod";
import { LIMITS } from "./constants.js";

function isValidIso8601(value: string): boolean {
  const parsed = Date.parse(value);
  return !Number.isNaN(parsed);
}

export const uafPayloadSchema = z.object({
  subject: z
    .string()
    .min(1, "subject must not be empty")
    .max(LIMITS.subjectMax, `subject must be at most ${LIMITS.subjectMax} characters`),
  date: z
    .string()
    .min(1, "date must not be empty")
    .refine(isValidIso8601, "date must be valid ISO 8601"),
  content: z
    .string()
    .min(1, "content must not be empty")
    .max(LIMITS.contentMax, `content must be at most ${LIMITS.contentMax} characters`),
  tags: z
    .array(
      z
        .string()
        .min(1, "tag must not be empty")
        .max(LIMITS.tagMax, `each tag must be at most ${LIMITS.tagMax} characters`)
        .refine((t) => !t.includes(";"), 'tag must not contain ";"'),
    )
    .max(LIMITS.tagCountMax, `at most ${LIMITS.tagCountMax} tags allowed`),
});
