import { describe, expect, it } from "vitest";
import { UafError, UafErrorCode, type UafPayload } from "@uaf/core";
import { createUafHtml } from "./createUafHtml.js";
import {
  extractUafPayloadCsvFromHtml,
  extractUafPayloadFromHtml,
} from "./extractUafHtml.js";

const payload: UafPayload = {
  subject: "数学 & 几何",
  date: "2026-05-19",
  content: "完成 <第1题>\n拍照上传 & 备注",
  tags: ["必做", "A&B"],
};

describe("extractUafPayloadFromHtml", () => {
  it("round-trips the embedded CSV payload from generated HTML", () => {
    const html = createUafHtml(payload);

    expect(extractUafPayloadFromHtml(html)).toEqual(payload);
    expect(extractUafPayloadCsvFromHtml(html)).toContain("subject,date,content,tags");
  });

  it("throws a UAF no-payload error when the template is missing", () => {
    expect(() => extractUafPayloadFromHtml("<!DOCTYPE html><html></html>")).toThrow(
      UafError,
    );

    try {
      extractUafPayloadFromHtml("<!DOCTYPE html><html></html>");
    } catch (e) {
      expect(e).toBeInstanceOf(UafError);
      expect((e as UafError).code).toBe(UafErrorCode.NoPayload);
    }
  });
});
