#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Command } from "commander";
import { parsePayload, UafError, UafErrorCode, type UafPayload } from "@uaf/core";
import {
  createUafHtml,
  createUafPdfFromHtml,
  extractUafPayloadCsvFromHtml,
  extractUafPayloadFromHtml,
  validateUafHtml,
} from "@uaf/html";
import { createUafPdf, extractUafPayload, extractUafPayloadCsv, validateUafPdf } from "@uaf/pdf";

const EXIT_OK = 0;
const EXIT_USER = 1;
const EXIT_UAF = 2;
const DEFAULT_RENDERER = "html";

type CreateRenderer = "html" | "pdf";
type DateDisplay = "zh" | "iso";
interface PayloadInputOptions {
  from?: string;
  subject?: string;
  date?: string;
  content?: string;
  tags?: string;
}

const program = new Command();

program.name("uaf").description("Unified Assignment Format (UAF) v1.0 CLI").version("1.0.0");

program
  .command("create")
  .description("Create a UAF PDF from payload fields or a CSV file")
  .requiredOption("-o, --output <path>", "Output PDF path")
  .option("--from <csv>", "Read payload from uaf_payload.csv file")
  .option(
    "--renderer <renderer>",
    "PDF renderer: html for browser print layout, pdf for the legacy native renderer",
    DEFAULT_RENDERER,
  )
  .option("--date-display <mode>", "HTML renderer date display: zh or iso", "zh")
  .option("--subject <subject>", "Assignment subject")
  .option("--date <date>", "Assignment date (ISO 8601)")
  .option("--content <content>", "Assignment content")
  .option("--tags <tags>", "Semicolon-separated tags")
  .action(async (opts: PayloadInputOptions & {
    output: string;
    renderer?: string;
    dateDisplay?: string;
  }) => {
    try {
      const outPath = resolve(opts.output);
      const payload = await readPayload(opts);
      const pdfBytes = await createPdf(payload, opts);

      await writeFile(outPath, pdfBytes);
      console.log(`Created: ${outPath}`);
      process.exit(EXIT_OK);
    } catch (e) {
      printError(e);
      process.exit(EXIT_USER);
    }
  });

program
  .command("render-html")
  .description("Render a self-contained printable UAF HTML document")
  .requiredOption("-o, --output <path>", "Output HTML path")
  .option("--from <csv>", "Read payload from uaf_payload.csv file")
  .option("--date-display <mode>", "HTML date display: zh or iso", "zh")
  .option("--subject <subject>", "Assignment subject")
  .option("--date <date>", "Assignment date (ISO 8601)")
  .option("--content <content>", "Assignment content")
  .option("--tags <tags>", "Semicolon-separated tags")
  .action(async (opts: PayloadInputOptions & {
    output: string;
    dateDisplay?: string;
  }) => {
    try {
      const outPath = resolve(opts.output);
      const payload = await readPayload(opts);
      const html = createUafHtml(payload, {
        dateDisplay: parseDateDisplay(opts.dateDisplay),
      });

      await writeFile(outPath, html, "utf-8");
      console.log(`Created: ${outPath}`);
      process.exit(EXIT_OK);
    } catch (e) {
      printError(e);
      process.exit(EXIT_USER);
    }
  });

program
  .command("extract")
  .description("Extract uaf_payload.csv from a UAF PDF")
  .argument("<pdf>", "Input PDF path")
  .option("-o, --output <path>", "Write CSV to file (default: stdout)")
  .option("--json", "Output payload as JSON instead of CSV")
  .action(async (pdfPath: string, opts: { output?: string; json?: boolean }) => {
    try {
      const bytes = new Uint8Array(await readFile(resolve(pdfPath)));
      if (opts.json) {
        const payload = await extractUafPayload(bytes);
        const text = JSON.stringify(payload, null, 2);
        if (opts.output) {
          await writeFile(resolve(opts.output), text, "utf-8");
        } else {
          console.log(text);
        }
      } else {
        const csv = await extractUafPayloadCsv(bytes);
        if (opts.output) {
          await writeFile(resolve(opts.output), csv, "utf-8");
        } else {
          process.stdout.write(csv);
        }
      }
      process.exit(EXIT_OK);
    } catch (e) {
      printError(e);
      if (
        e instanceof UafError &&
        (e.code === UafErrorCode.NoPayload || e.code === UafErrorCode.CorruptPdf)
      ) {
        process.exit(EXIT_UAF);
      }
      process.exit(EXIT_USER);
    }
  });

program
  .command("extract-html")
  .description("Extract uaf_payload.csv from a UAF HTML document")
  .argument("<html>", "Input HTML path")
  .option("-o, --output <path>", "Write CSV to file (default: stdout)")
  .option("--json", "Output payload as JSON instead of CSV")
  .action(async (htmlPath: string, opts: { output?: string; json?: boolean }) => {
    try {
      const html = await readFile(resolve(htmlPath), "utf-8");
      if (opts.json) {
        const payload = extractUafPayloadFromHtml(html);
        const text = JSON.stringify(payload, null, 2);
        if (opts.output) {
          await writeFile(resolve(opts.output), text, "utf-8");
        } else {
          console.log(text);
        }
      } else {
        const csv = extractUafPayloadCsvFromHtml(html);
        if (opts.output) {
          await writeFile(resolve(opts.output), csv, "utf-8");
        } else {
          process.stdout.write(csv);
        }
      }
      process.exit(EXIT_OK);
    } catch (e) {
      printError(e);
      if (e instanceof UafError && e.code === UafErrorCode.NoPayload) {
        process.exit(EXIT_UAF);
      }
      process.exit(EXIT_USER);
    }
  });

program
  .command("validate")
  .description("Validate a UAF PDF (embedded payload + single page)")
  .argument("<pdf>", "Input PDF path")
  .action(async (pdfPath: string) => {
    try {
      const bytes = new Uint8Array(await readFile(resolve(pdfPath)));
      const result = await validateUafPdf(bytes);
      if (result.valid) {
        console.log("Valid UAF PDF");
        console.log(JSON.stringify(result.payload, null, 2));
        process.exit(EXIT_OK);
      }
      console.error("Invalid UAF PDF:");
      for (const err of result.errors) {
        console.error(`  - ${err}`);
      }
      process.exit(EXIT_UAF);
    } catch (e) {
      printError(e);
      process.exit(EXIT_UAF);
    }
  });

program
  .command("validate-html")
  .description("Validate a UAF HTML document (embedded payload template)")
  .argument("<html>", "Input HTML path")
  .action(async (htmlPath: string) => {
    try {
      const html = await readFile(resolve(htmlPath), "utf-8");
      const result = validateUafHtml(html);
      if (result.valid) {
        console.log("Valid UAF HTML");
        console.log(JSON.stringify(result.payload, null, 2));
        process.exit(EXIT_OK);
      }
      console.error("Invalid UAF HTML:");
      for (const err of result.errors) {
        console.error(`  - ${err}`);
      }
      process.exit(EXIT_UAF);
    } catch (e) {
      printError(e);
      process.exit(EXIT_UAF);
    }
  });

function parseRenderer(value: string | undefined): CreateRenderer {
  if (value === "html" || value === "pdf") {
    return value;
  }
  throw new Error(`Invalid --renderer "${value}". Expected "html" or "pdf".`);
}

function parseDateDisplay(value: string | undefined): DateDisplay {
  if (value === "zh" || value === "iso") {
    return value;
  }
  throw new Error(`Invalid --date-display "${value}". Expected "zh" or "iso".`);
}

function parseTags(value: string | undefined): string[] {
  return value
    ? value
        .split(";")
        .map((tag) => tag.trim())
        .filter(Boolean)
    : [];
}

async function readPayload(opts: PayloadInputOptions): Promise<UafPayload> {
  if (opts.from) {
    return parsePayload(await readFile(resolve(opts.from), "utf-8"));
  }

  if (!opts.subject || !opts.date || !opts.content) {
    throw new Error("--subject, --date, and --content are required unless --from is used");
  }

  return {
    subject: opts.subject,
    date: opts.date,
    content: opts.content,
    tags: parseTags(opts.tags),
  };
}

async function createPdf(
  payload: UafPayload,
  opts: { renderer?: string; dateDisplay?: string },
): Promise<Uint8Array> {
  const renderer = parseRenderer(opts.renderer ?? DEFAULT_RENDERER);

  if (renderer === "html") {
    return createUafPdfFromHtml(payload, {
      dateDisplay: parseDateDisplay(opts.dateDisplay),
    });
  }

  return createUafPdf(payload);
}

function printError(e: unknown): void {
  if (e instanceof UafError) {
    console.error(`Error [${e.code}]: ${e.message}`);
  } else if (e instanceof Error) {
    console.error(`Error: ${e.message}`);
  } else {
    console.error("Unknown error");
  }
}

program.parse();
