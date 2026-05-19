import {
  PDFArray,
  PDFDict,
  PDFDocument,
  PDFHexString,
  PDFName,
  PDFRawStream,
  PDFStream,
  PDFString,
  decodePDFRawStream,
} from "pdf-lib";
import { UAF_PAYLOAD_FILENAME, UafError, UafErrorCode } from "@uaf/core";

function decodePdfString(value: PDFString | PDFHexString): string {
  return value.decodeText();
}

function collectNameTreeLeaves(
  node: PDFDict,
  context: PDFDocument["context"],
): Array<{ name: string; fileSpec: PDFDict }> {
  const results: Array<{ name: string; fileSpec: PDFDict }> = [];

  const names = node.lookupMaybe(PDFName.of("Names"), PDFArray);
  if (names) {
    for (let i = 0; i < names.size(); i += 2) {
      const nameObj = names.get(i);
      const valObj = names.get(i + 1);
      if (!nameObj || !valObj) continue;

      let name: string | undefined;
      if (nameObj instanceof PDFString || nameObj instanceof PDFHexString) {
        name = decodePdfString(nameObj);
      } else {
        continue;
      }

      const fileSpec = context.lookup(valObj, PDFDict);
      if (fileSpec) {
        results.push({ name, fileSpec });
      }
    }
  }

  const kids = node.lookupMaybe(PDFName.of("Kids"), PDFArray);
  if (kids) {
    for (let i = 0; i < kids.size(); i++) {
      const kid = kids.get(i);
      const kidDict = context.lookup(kid, PDFDict);
      if (kidDict) {
        results.push(...collectNameTreeLeaves(kidDict, context));
      }
    }
  }

  return results;
}

function getEmbeddedFileBytes(fileSpec: PDFDict, context: PDFDocument["context"]): Uint8Array | undefined {
  const ef = fileSpec.lookupMaybe(PDFName.of("EF"), PDFDict);
  if (!ef) return undefined;

  const streamRef = ef.get(PDFName.of("F")) ?? ef.get(PDFName.of("UF"));
  if (!streamRef) return undefined;

  const stream = context.lookup(streamRef);
  if (stream instanceof PDFRawStream) {
    return decodePDFRawStream(stream).decode();
  }
  if (stream instanceof PDFStream) {
    return stream.getContents();
  }

  return undefined;
}

function getFileSpecName(fileSpec: PDFDict): string | undefined {
  const uf = fileSpec.get(PDFName.of("UF"));
  if (uf instanceof PDFString || uf instanceof PDFHexString) {
    return decodePdfString(uf);
  }

  const f = fileSpec.get(PDFName.of("F"));
  if (f instanceof PDFString || f instanceof PDFHexString) {
    return decodePdfString(f);
  }

  return undefined;
}

export async function extractEmbeddedFile(
  pdfBytes: Uint8Array,
  fileName: string = UAF_PAYLOAD_FILENAME,
): Promise<Uint8Array> {
  let pdfDoc: PDFDocument;
  try {
    pdfDoc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  } catch (cause) {
    throw new UafError(UafErrorCode.CorruptPdf, "Failed to load PDF", cause);
  }

  const context = pdfDoc.context;
  const catalog = pdfDoc.catalog;

  const namesDict = catalog.lookupMaybe(PDFName.of("Names"), PDFDict);
  if (namesDict) {
    const embeddedFiles = namesDict.lookupMaybe(PDFName.of("EmbeddedFiles"), PDFDict);
    if (embeddedFiles) {
      const entries = collectNameTreeLeaves(embeddedFiles, context);
      for (const entry of entries) {
        const specName = getFileSpecName(entry.fileSpec) ?? entry.name;
        if (specName === fileName || entry.name === fileName) {
          const bytes = getEmbeddedFileBytes(entry.fileSpec, context);
          if (bytes && bytes.length > 0) {
            return bytes;
          }
        }
      }
    }
  }

  const af = catalog.lookupMaybe(PDFName.of("AF"), PDFArray);
  if (af) {
    for (let i = 0; i < af.size(); i++) {
      const fileSpec = context.lookup(af.get(i), PDFDict);
      if (!fileSpec) continue;
      const specName = getFileSpecName(fileSpec);
      if (specName === fileName) {
        const bytes = getEmbeddedFileBytes(fileSpec, context);
        if (bytes && bytes.length > 0) {
          return bytes;
        }
      }
    }
  }

  throw new UafError(
    UafErrorCode.NoPayload,
    `Embedded file "${fileName}" not found`,
  );
}
