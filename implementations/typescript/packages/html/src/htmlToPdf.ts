import { spawn } from "node:child_process";
import { access, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

type PdfWaitUntil = "load" | "domcontentloaded" | "networkidle0" | "networkidle2";

interface PdfPage {
  setContent(html: string, options: { waitUntil: PdfWaitUntil }): Promise<void>;
  pdf(options: {
    width: string;
    height: string;
    printBackground: boolean;
    preferCSSPageSize: boolean;
  }): Promise<Uint8Array | Buffer>;
  close(): Promise<void>;
}

interface PdfBrowser {
  newPage(): Promise<PdfPage>;
  close(): Promise<void>;
}

interface PuppeteerModule {
  launch(options?: Record<string, unknown>): Promise<PdfBrowser>;
}

export interface HtmlToPdfOptions {
  /**
   * Optional Puppeteer browser instance to reuse.
   * If not provided, a new browser will be launched and closed automatically.
   */
  browser?: PdfBrowser;
  /**
   * Options passed to puppeteer.launch() when this function creates the browser.
   */
  launchOptions?: Record<string, unknown>;
  /**
   * Optional Chrome/Edge executable for direct headless print-to-pdf fallback.
   */
  browserExecutablePath?: string;
  /**
   * Additional arguments passed before the generated print-to-pdf arguments.
   */
  browserArgs?: string[];
  /**
   * Page readiness signal before printing. Defaults to "networkidle0".
   */
  waitUntil?: PdfWaitUntil;
  /**
   * Paper width. Defaults to "210mm" (A4 width).
   */
  width?: string;
  /**
   * Paper height. Defaults to "297mm" (A4 height).
   */
  height?: string;
  /**
   * Whether to print background graphics. Defaults to true.
   */
  printBackground?: boolean;
}

/**
 * Convert an HTML string to a PDF byte array using a browser print pipeline.
 *
 * Puppeteer is preferred when available. If it is not installed, the function
 * falls back to a local Chrome/Edge executable when one can be found.
 */
export async function htmlToPdf(
  html: string,
  options: HtmlToPdfOptions = {},
): Promise<Uint8Array> {
  if (options.browser) {
    return printWithPuppeteerBrowser(html, options.browser, options, false);
  }

  if (options.browserExecutablePath) {
    return printWithBrowserExecutable(html, options.browserExecutablePath, options);
  }

  try {
    const browser = await launchPuppeteerBrowser(options.launchOptions);
    return await printWithPuppeteerBrowser(html, browser, options, true);
  } catch (e) {
    const executablePath = await findBrowserExecutable();
    if (executablePath) {
      return printWithBrowserExecutable(html, executablePath, options);
    }

    const details = e instanceof Error ? ` ${e.message}` : "";
    throw new Error(
      "HTML-to-PDF conversion requires Puppeteer or a local Chrome/Edge executable." +
        `${details} Install Puppeteer, set UAF_CHROMIUM_EXECUTABLE, or use --renderer pdf.`,
    );
  }
}

async function printWithPuppeteerBrowser(
  html: string,
  browser: PdfBrowser,
  options: HtmlToPdfOptions,
  closeBrowser: boolean,
): Promise<Uint8Array> {
  let page: PdfPage | undefined;

  try {
    page = await browser.newPage();
    await page.setContent(html, { waitUntil: options.waitUntil ?? "networkidle0" });

    const pdfBuffer = await page.pdf({
      width: options.width ?? "210mm",
      height: options.height ?? "297mm",
      printBackground: options.printBackground ?? true,
      preferCSSPageSize: true,
    });

    return new Uint8Array(pdfBuffer);
  } finally {
    if (page) {
      await page.close().catch(() => {
        /* ignore */
      });
    }
    if (closeBrowser) {
      await browser.close().catch(() => {
        /* ignore */
      });
    }
  }
}

async function launchPuppeteerBrowser(
  launchOptions?: Record<string, unknown>,
): Promise<PdfBrowser> {
  let puppeteerModule: PuppeteerModule | undefined;
  try {
    const packageName = "puppeteer";
    puppeteerModule = (await import(packageName)) as PuppeteerModule;
  } catch {
    throw new Error(
      "Puppeteer is required for HTML-to-PDF conversion. " +
        "Install it with: pnpm add -D puppeteer or use --renderer pdf.",
    );
  }

  return puppeteerModule.launch(launchOptions);
}

async function printWithBrowserExecutable(
  html: string,
  executablePath: string,
  options: HtmlToPdfOptions,
): Promise<Uint8Array> {
  const tempDir = await mkdtemp(join(tmpdir(), "uaf-html-"));
  const htmlPath = join(tempDir, "input.html");
  const pdfPath = join(tempDir, "output.pdf");

  try {
    await writeFile(htmlPath, html, "utf-8");
    await runBrowserPrint(executablePath, [
      ...(options.browserArgs ?? []),
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      `--print-to-pdf=${pdfPath}`,
      "--print-to-pdf-no-header",
      pathToFileURL(htmlPath).href,
    ]);
    return new Uint8Array(await readFile(pdfPath));
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

async function runBrowserPrint(executablePath: string, args: string[]): Promise<void> {
  const { code, stderr } = await new Promise<{ code: number | null; stderr: string }>((resolve) => {
    const child = spawn(executablePath, args, {
      windowsHide: true,
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";

    child.stderr.setEncoding("utf-8");
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("close", (code) => resolve({ code, stderr }));
    child.on("error", (error) => resolve({ code: 1, stderr: error.message }));
  });

  if (code !== 0) {
    throw new Error(`Browser print-to-pdf failed with exit code ${code}: ${stderr.trim()}`);
  }
}

async function findBrowserExecutable(): Promise<string | undefined> {
  const candidates = [
    process.env.UAF_CHROMIUM_EXECUTABLE,
    process.env.PUPPETEER_EXECUTABLE_PATH,
    process.env.CHROME_PATH,
    process.platform === "win32"
      ? `${process.env.PROGRAMFILES ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env["PROGRAMFILES(X86)"] ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env.LOCALAPPDATA ?? ""}\\Google\\Chrome\\Application\\chrome.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env.PROGRAMFILES ?? ""}\\Microsoft\\Edge\\Application\\msedge.exe`
      : undefined,
    process.platform === "win32"
      ? `${process.env["PROGRAMFILES(X86)"] ?? ""}\\Microsoft\\Edge\\Application\\msedge.exe`
      : undefined,
    process.platform === "darwin"
      ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      : undefined,
    process.platform === "darwin"
      ? "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
      : undefined,
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/microsoft-edge",
  ].filter((candidate): candidate is string => Boolean(candidate));

  for (const candidate of candidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      // Try the next known browser path.
    }
  }

  return undefined;
}
