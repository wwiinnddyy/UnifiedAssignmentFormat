import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createUafHtml: vi.fn(),
  createUafPdf: vi.fn(),
  createUafPdfFromHtml: vi.fn(),
  extractUafPayload: vi.fn(),
  extractUafPayloadCsv: vi.fn(),
  extractUafPayloadCsvFromHtml: vi.fn(),
  extractUafPayloadFromHtml: vi.fn(),
  readFile: vi.fn(),
  validateUafHtml: vi.fn(),
  validateUafPdf: vi.fn(),
  writeFile: vi.fn(),
}));

vi.mock("node:fs/promises", () => ({
  readFile: mocks.readFile,
  writeFile: mocks.writeFile,
}));

vi.mock("@uaf/html", () => ({
  createUafHtml: mocks.createUafHtml,
  createUafPdfFromHtml: mocks.createUafPdfFromHtml,
  extractUafPayloadCsvFromHtml: mocks.extractUafPayloadCsvFromHtml,
  extractUafPayloadFromHtml: mocks.extractUafPayloadFromHtml,
  validateUafHtml: mocks.validateUafHtml,
}));

vi.mock("@uaf/pdf", () => ({
  createUafPdf: mocks.createUafPdf,
  extractUafPayload: mocks.extractUafPayload,
  extractUafPayloadCsv: mocks.extractUafPayloadCsv,
  validateUafPdf: mocks.validateUafPdf,
}));

const payloadArgs = [
  "--subject",
  "Math",
  "--date",
  "2026-06-08",
  "--content",
  "Complete page 45 exercises.",
  "--tags",
  "required;geometry",
];

const payload = {
  subject: "Math",
  date: "2026-06-08",
  content: "Complete page 45 exercises.",
  tags: ["required", "geometry"],
};

describe("uaf CLI smoke tests", () => {
  beforeEach(() => {
    vi.resetModules();
    for (const mock of Object.values(mocks)) {
      mock.mockReset();
    }
    mocks.writeFile.mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders a self-contained HTML document", async () => {
    const html = "<!DOCTYPE html><html><body>UAF</body></html>";
    mocks.createUafHtml.mockReturnValue(html);

    const run = await runCli([
      "render-html",
      "-o",
      "assignment.html",
      "--date-display",
      "iso",
      ...payloadArgs,
    ]);

    expect(mocks.createUafHtml).toHaveBeenCalledWith(payload, {
      dateDisplay: "iso",
    });
    expect(mocks.writeFile).toHaveBeenCalledWith(
      resolve("assignment.html"),
      html,
      "utf-8",
    );
    expect(run.exitSpy).toHaveBeenCalledWith(0);
  });

  it("validates an HTML document", async () => {
    const html = "<!DOCTYPE html><html><body>UAF</body></html>";
    mocks.readFile.mockResolvedValue(html);
    mocks.validateUafHtml.mockReturnValue({
      valid: true,
      payload,
      errors: [],
    });

    const run = await runCli(["validate-html", "assignment.html"]);

    expect(mocks.readFile).toHaveBeenCalledWith(resolve("assignment.html"), "utf-8");
    expect(mocks.validateUafHtml).toHaveBeenCalledWith(html);
    expect(run.logSpy).toHaveBeenCalledWith("Valid UAF HTML");
    expect(run.exitSpy).toHaveBeenCalledWith(0);
  });

  it("extracts CSV from an HTML document", async () => {
    const html = "<!DOCTYPE html><html><body>UAF</body></html>";
    const csv = "subject,date,content,tags\nMath,2026-06-08,Work,required\n";
    mocks.readFile.mockResolvedValue(html);
    mocks.extractUafPayloadCsvFromHtml.mockReturnValue(csv);

    const run = await runCli(["extract-html", "assignment.html"]);

    expect(mocks.readFile).toHaveBeenCalledWith(resolve("assignment.html"), "utf-8");
    expect(mocks.extractUafPayloadCsvFromHtml).toHaveBeenCalledWith(html);
    expect(run.stdoutSpy).toHaveBeenCalledWith(csv);
    expect(run.exitSpy).toHaveBeenCalledWith(0);
  });

  it("uses the HTML renderer for create by default", async () => {
    const pdfBytes = new Uint8Array([1, 2, 3]);
    mocks.createUafPdfFromHtml.mockResolvedValue(pdfBytes);

    const run = await runCli(["create", "-o", "assignment.pdf", ...payloadArgs]);

    expect(mocks.createUafPdfFromHtml).toHaveBeenCalledWith(payload, {
      dateDisplay: "zh",
    });
    expect(mocks.createUafPdf).not.toHaveBeenCalled();
    expect(mocks.writeFile).toHaveBeenCalledWith(resolve("assignment.pdf"), pdfBytes);
    expect(run.exitSpy).toHaveBeenCalledWith(0);
  });

  it("uses the legacy native PDF renderer when requested", async () => {
    const pdfBytes = new Uint8Array([9, 8, 7]);
    mocks.createUafPdf.mockResolvedValue(pdfBytes);

    const run = await runCli([
      "create",
      "-o",
      "legacy.pdf",
      "--renderer",
      "pdf",
      ...payloadArgs,
    ]);

    expect(mocks.createUafPdf).toHaveBeenCalledWith(payload);
    expect(mocks.createUafPdfFromHtml).not.toHaveBeenCalled();
    expect(mocks.writeFile).toHaveBeenCalledWith(resolve("legacy.pdf"), pdfBytes);
    expect(run.exitSpy).toHaveBeenCalledWith(0);
  });
});

async function runCli(args: string[]) {
  const originalArgv = process.argv;
  process.argv = ["node", "uaf", ...args];

  const exitSpy = vi.spyOn(process, "exit").mockImplementation(((_code) => {
    return undefined as never;
  }) as typeof process.exit);
  const logSpy = vi.spyOn(console, "log").mockImplementation(() => undefined);
  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
  const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);

  try {
    await import("./cli.js");
    await vi.waitFor(() => expect(exitSpy).toHaveBeenCalled(), {
      timeout: 1_000,
    });
  } finally {
    process.argv = originalArgv;
  }

  return {
    errorSpy,
    exitSpy,
    logSpy,
    stdoutSpy,
  };
}
