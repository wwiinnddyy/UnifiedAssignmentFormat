import { CSV_HEADER, FIELD_NAMES } from "./constants.js";
import { UafError, UafErrorCode } from "./errors.js";
import type { UafPayload } from "./types.js";
import { uafPayloadSchema } from "./schema.js";

/** Escape a single CSV field per RFC 4180 */
function escapeField(value: string): string {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

/** Parse one CSV row into fields (handles quoted fields with commas and newlines) */
function parseCsvRow(line: string): string[] {
  const fields: string[] = [];
  let current = "";
  let inQuotes = false;
  let i = 0;

  while (i < line.length) {
    const ch = line[i];

    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          current += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      current += ch;
      i++;
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
      i++;
      continue;
    }

    if (ch === ",") {
      fields.push(current);
      current = "";
      i++;
      continue;
    }

    current += ch;
    i++;
  }

  fields.push(current);
  return fields;
}

/** Split CSV text into logical rows (quoted fields may contain newlines) */
function splitCsvRows(text: string): string[] {
  const rows: string[] = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (ch === '"') {
      const prev = text[i - 1];
      const isEscaped = prev === '"' && inQuotes;
      if (!isEscaped) {
        inQuotes = !inQuotes;
      }
    }

    if ((ch === "\n" || ch === "\r") && !inQuotes) {
      if (ch === "\r" && text[i + 1] === "\n") {
        i++;
      }
      if (current.trim().length > 0) {
        rows.push(current);
      }
      current = "";
      continue;
    }

    current += ch;
  }

  if (current.trim().length > 0) {
    rows.push(current);
  }

  return rows;
}

function tagsFromCsv(tagsCol: string): string[] {
  if (!tagsCol.trim()) {
    return [];
  }
  return tagsCol
    .split(";")
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

function tagsToCsv(tags: string[]): string {
  return tags.join(";");
}

export function serializePayload(payload: UafPayload): string {
  const validated = uafPayloadSchema.parse(payload);
  const row = [
    escapeField(validated.subject),
    escapeField(validated.date),
    escapeField(validated.content),
    escapeField(tagsToCsv(validated.tags)),
  ].join(",");
  return `${CSV_HEADER}\n${row}\n`;
}

export function parsePayload(csv: string): UafPayload {
  const normalized = csv.replace(/^\uFEFF/, "").trim();
  const rows = splitCsvRows(normalized);

  if (rows.length < 2) {
    throw new UafError(UafErrorCode.InvalidCsv, "CSV must contain header and exactly one data row");
  }

  if (rows.length > 2) {
    throw new UafError(UafErrorCode.InvalidCsv, "CSV must contain exactly one data row");
  }

  const headerFields = parseCsvRow(rows[0]);
  const dataFields = parseCsvRow(rows[1]);

  if (headerFields.join(",") !== CSV_HEADER) {
    throw new UafError(
      UafErrorCode.InvalidCsv,
      `Invalid header: expected "${CSV_HEADER}", got "${headerFields.join(",")}"`,
    );
  }

  if (dataFields.length !== FIELD_NAMES.length) {
    throw new UafError(
      UafErrorCode.InvalidCsv,
      `Expected ${FIELD_NAMES.length} columns, got ${dataFields.length}`,
    );
  }

  const [subject, date, content, tagsCol] = dataFields;
  const payload: UafPayload = {
    subject,
    date,
    content,
    tags: tagsFromCsv(tagsCol),
  };

  const result = uafPayloadSchema.safeParse(payload);
  if (!result.success) {
    throw new UafError(
      UafErrorCode.InvalidPayload,
      result.error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join("; "),
    );
  }

  return result.data;
}

export function validatePayload(payload: unknown): UafPayload {
  const result = uafPayloadSchema.safeParse(payload);
  if (!result.success) {
    throw new UafError(
      UafErrorCode.InvalidPayload,
      result.error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join("; "),
    );
  }
  return result.data;
}
