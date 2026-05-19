#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Command } from "commander";
import { UafError, UafErrorCode } from "@uaf/core";
import { createUafPdf, createUafPdfFromCsv, extractUafPayload, extractUafPayloadCsv, validateUafPdf } from "@uaf/pdf";

const EXIT_OK = 0;
const EXIT_USER = 1;
const EXIT_UAF = 2;

const program = new Command();

program.name("uaf").description("Unified Assignment Format (UAF) v1.0 CLI").version("1.0.0");

program
  .command("create")
  .description("Create a UAF PDF from payload fields or a CSV file")
  .requiredOption("-o, --output <path>", "Output PDF path")
  .option("--from <csv>", "Read payload from uaf_payload.csv file")
  .option("--subject <subject>", "Assignment subject")
  .option("--date <date>", "Assignment date (ISO 8601)")
  .option("--content <content>", "Assignment content")
  .option("--tags <tags>", "Semicolon-separated tags")
  .action(async (opts: {
    output: string;
    from?: string;
    subject?: string;
    date?: string;
    content?: string;
    tags?: string;
  }) => {
    try {
      const outPath = resolve(opts.output);
      let pdfBytes: Uint8Array;

      if (opts.from) {
        const csv = await readFile(resolve(opts.from), "utf-8");
        pdfBytes = await createUafPdfFromCsv(csv);
      } else {
        if (!opts.subject || !opts.date || !opts.content) {
          console.error("Error: --subject, --date, and --content are required unless --from is used");
          process.exit(EXIT_USER);
        }
        const tags = opts.tags
          ? opts.tags
              .split(";")
              .map((t) => t.trim())
              .filter(Boolean)
          : [];
        pdfBytes = await createUafPdf({
          subject: opts.subject,
          date: opts.date,
          content: opts.content,
          tags,
        });
      }

      await writeFile(outPath, pdfBytes);
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
