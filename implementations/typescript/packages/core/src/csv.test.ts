import { describe, expect, it } from "vitest";
import { UafError, UafErrorCode } from "./errors.js";
import { parsePayload, serializePayload, validatePayload } from "./csv.js";
import type { UafDocument } from "./types.js";

const document: UafDocument = [
  {
    subject: "Math",
    date: "2026-05-19",
    content: 'Complete exercises 1, 2 and say "done".',
    tags: ["required", "geometry"],
  },
  {
    subject: "Chinese",
    date: "2026-05-19",
    content: "Read the poem\nCopy the second paragraph",
    tags: [],
  },
];

describe("serializePayload / parsePayload", () => {
  it("round-trips multiple assignments in source order", () => {
    const csv = serializePayload(document);
    expect(parsePayload(csv)).toEqual(document);
    expect(csv.split("\n")[0]).toBe("subject,date,content,tags");
  });

  it("keeps single-assignment documents valid", () => {
    const single: UafDocument = [document[0]];
    expect(parsePayload(serializePayload(single))).toEqual(single);
  });

  it("handles multiline content, commas, and quotes", () => {
    const csv = serializePayload(document);
    expect(csv).toContain('"Read the poem\nCopy the second paragraph"');
    expect(csv).toContain('""done""');
    expect(parsePayload(csv)).toEqual(document);
  });

  it("rejects a header without assignments", () => {
    expect(() => parsePayload("subject,date,content,tags\n")).toThrow(UafError);
    expect(() => validatePayload([])).toThrow(UafError);
  });

  it("identifies the invalid row", () => {
    const csv = `subject,date,content,tags\nMath,2026-05-19,Work,\nChinese,not-a-date,Read,`;
    try {
      parsePayload(csv);
      throw new Error("Expected parsePayload to fail");
    } catch (error) {
      expect(error).toBeInstanceOf(UafError);
      expect((error as UafError).code).toBe(UafErrorCode.InvalidPayload);
      expect((error as Error).message).toContain("Row 3");
    }
  });

  it("rejects tags containing semicolons", () => {
    expect(() =>
      serializePayload([
        {
          subject: "Math",
          date: "2026-05-19",
          content: "Work",
          tags: ["a;b"],
        },
      ]),
    ).toThrow(UafError);
  });
});
