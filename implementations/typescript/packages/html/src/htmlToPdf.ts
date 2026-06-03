import type { Browser, Page } from "puppeteer";

export interface HtmlToPdfOptions {
  /**
   * Optional Puppeteer browser instance to reuse.
   * If not provided, a new browser will be launched and closed automatically.
   */
  browser?: Browser;
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
 * Convert an HTML string to a PDF byte array using Puppeteer.
 *
 * Puppeteer is an optional dependency. If it is not installed, this function
 * will throw an error directing the user to install it.
 */
export async function htmlToPdf(
  html: string,
  options: HtmlToPdfOptions = {},
): Promise<Uint8Array> {
  let puppeteerModule: typeof import("puppeteer") | undefined;
  try {
    puppeteerModule = await import("puppeteer");
  } catch {
    throw new Error(
      "Puppeteer is required for HTML-to-PDF conversion. " +
        "Install it with: npm install puppeteer",
    );
  }

  const browser: Browser =
    options.browser ?? (await puppeteerModule.launch());
  let page: Page | undefined;

  try {
    page = await browser.newPage();
    await page.setContent(html, { waitUntil: "networkidle0" });

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
    if (!options.browser) {
      await browser.close().catch(() => {
        /* ignore */
      });
    }
  }
}