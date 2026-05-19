import { describe, expect, it } from "vitest";
import { UafError, UafErrorCode } from "./errors.js";
import { parsePayload, serializePayload } from "./csv.js";

describe("serializePayload / parsePayload", () => {
  it("round-trips simple payload", () => {
    const payload = {
      subject: "数学",
      date: "2026-05-19",
      content: "完成课本第45页第1、2题，请拍照上传。",
      tags: ["必做", "几何"],
    };
    const csv = serializePayload(payload);
    expect(parsePayload(csv)).toEqual(payload);
  });

  it("handles multiline content", () => {
    const payload = {
      subject: "语文",
      date: "2026-05-19",
      content: "背诵《静夜思》\n第二段抄写生字",
      tags: ["必做"],
    };
    const csv = serializePayload(payload);
    expect(parsePayload(csv)).toEqual(payload);
  });

  it("handles empty tags", () => {
    const payload = {
      subject: "英语",
      date: "2026-05-19",
      content: "朗读课文 Unit 3",
      tags: [] as string[],
    };
    const csv = serializePayload(payload);
    expect(parsePayload(csv)).toEqual(payload);
  });

  it("escapes commas and quotes in content", () => {
    const payload = {
      subject: "数学",
      date: "2026-05-19",
      content: 'Say "hello", world',
      tags: [] as string[],
    };
    const csv = serializePayload(payload);
    expect(csv).toContain('""hello""');
    expect(parsePayload(csv)).toEqual(payload);
  });

  it("rejects invalid date", () => {
    const csv = `subject,date,content,tags
数学,not-a-date,作业内容,`;
    expect(() => parsePayload(csv)).toThrow(UafError);
    try {
      parsePayload(csv);
    } catch (e) {
      expect((e as UafError).code).toBe(UafErrorCode.InvalidPayload);
    }
  });

  it("rejects tag with semicolon", () => {
    expect(() =>
      serializePayload({
        subject: "数学",
        date: "2026-05-19",
        content: "作业",
        tags: ["a;b"],
      }),
    ).toThrow();
  });

  it("rejects extra data rows", () => {
    const csv = `subject,date,content,tags
数学,2026-05-19,作业,
数学,2026-05-20,作业2,`;
    expect(() => parsePayload(csv)).toThrow(UafError);
  });
});
