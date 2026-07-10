import { CSV_HEADER, FIELD_NAMES } from "./constants.js";
import { UafError, UafErrorCode } from "./errors.js";
import type { UafAssignment, UafDocument } from "./types.js";
import { uafAssignmentSchema, uafDocumentSchema } from "./schema.js";

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

export function serializePayload(document: UafDocument): string {
  const validated = validatePayload(document);
  const rows = validated.map((assignment) =>
    [
      escapeField(assignment.subject),
      escapeField(assignment.date),
      escapeField(assignment.content),
      escapeField(tagsToCsv(assignment.tags)),
    ].join(","),
  );
  return `${CSV_HEADER}\n${rows.join("\n")}\n`;
}

export function parsePayload(csv: string): UafDocument {
  const normalized = csv.replace(/^\uFEFF/, "").trim();
  const rows = splitCsvRows(normalized);

  if (rows.length < 2) {
    throw new UafError(UafErrorCode.InvalidCsv, "CSV must contain a header and at least one data row");
  }

  const headerFields = parseCsvRow(rows[0]);

  if (headerFields.join(",") !== CSV_HEADER) {
    throw new UafError(
      UafErrorCode.InvalidCsv,
      `Invalid header: expected "${CSV_HEADER}", got "${headerFields.join(",")}"`,
    );
  }

  const assignments: UafAssignment[] = rows.slice(1).map((row, index) => {
    const dataFields = parseCsvRow(row);
    if (dataFields.length !== FIELD_NAMES.length) {
      throw new UafError(
        UafErrorCode.InvalidCsv,
        `Row ${index + 2}: expected ${FIELD_NAMES.length} columns, got ${dataFields.length}`,
      );
    }

    const [subject, date, content, tagsCol] = dataFields;
    const result = uafAssignmentSchema.safeParse({
      subject,
      date,
      content,
      tags: tagsFromCsv(tagsCol),
    });
    if (!result.success) {
      throw new UafError(
        UafErrorCode.InvalidPayload,
        `Row ${index + 2}: ${result.error.errors
          .map((e) => `${e.path.join(".")}: ${e.message}`)
          .join("; ")}`,
      );
    }
    return result.data;
  });

  return assignments as UafDocument;
}

export function validatePayload(payload: unknown): UafDocument {
  const result = uafDocumentSchema.safeParse(payload);
  if (!result.success) {
    throw new UafError(
      UafErrorCode.InvalidPayload,
      result.error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join("; "),
    );
  }
  return result.data as UafDocument;
}
