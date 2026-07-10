import type { UafDocument } from "@uaf/core";

interface HarfBuzzExports {
  memory: WebAssembly.Memory;
  malloc(size: number): number;
  free(pointer: number): void;
  hb_subset_input_create_or_fail(): number;
  hb_subset_input_destroy(input: number): void;
  hb_subset_input_set(input: number, setType: number): number;
  hb_subset_input_unicode_set(input: number): number;
  hb_subset_input_get_flags(input: number): number;
  hb_subset_input_set_flags(input: number, flags: number): void;
  hb_set_clear(set: number): void;
  hb_set_invert(set: number): void;
  hb_set_add(set: number, value: number): void;
  hb_blob_create(data: number, length: number, mode: number, userData: number, destroy: number): number;
  hb_blob_destroy(blob: number): void;
  hb_face_create(blob: number, index: number): number;
  hb_face_destroy(face: number): void;
  hb_subset_or_fail(face: number, input: number): number;
  hb_face_reference_blob(face: number): number;
  hb_blob_get_data(blob: number, length: number): number;
  hb_blob_get_length(blob: number): number;
}

export function collectDocumentText(document: UafDocument): string {
  const parts = ["使用 UAF v1.0 导出正文下页继续（续）年月日"];
  for (const assignment of document) {
    parts.push(assignment.subject, assignment.date, assignment.content, ...assignment.tags);
  }
  return [...new Set(parts.join(""))].join("");
}

export async function subsetFontInBrowser(
  fontBytes: Uint8Array,
  text: string,
  wasmUrl: string | URL,
): Promise<Uint8Array> {
  const response = await fetch(wasmUrl);
  if (!response.ok) throw new Error(`Failed to load HarfBuzz subset engine: ${response.status}`);
  const result = await WebAssembly.instantiate(await response.arrayBuffer());
  const hb = result.instance.exports as unknown as HarfBuzzExports;
  const input = hb.hb_subset_input_create_or_fail();
  if (!input) throw new Error("HarfBuzz could not create a subset input");

  const fontPointer = hb.malloc(fontBytes.byteLength);
  new Uint8Array(hb.memory.buffer).set(fontBytes, fontPointer);
  const blob = hb.hb_blob_create(fontPointer, fontBytes.byteLength, 2, 0, 0);
  const face = hb.hb_face_create(blob, 0);
  hb.hb_blob_destroy(blob);

  try {
    const layoutFeatures = hb.hb_subset_input_set(input, 6);
    hb.hb_set_clear(layoutFeatures);
    hb.hb_set_invert(layoutFeatures);
    hb.hb_subset_input_set_flags(input, hb.hb_subset_input_get_flags(input) | 0x00000200);
    const unicodes = hb.hb_subset_input_unicode_set(input);
    for (const character of text) hb.hb_set_add(unicodes, character.codePointAt(0) ?? 0);

    const subsetFace = hb.hb_subset_or_fail(face, input);
    if (!subsetFace) throw new Error("HarfBuzz could not subset the UAF font");
    try {
      const resultBlob = hb.hb_face_reference_blob(subsetFace);
      try {
        const offset = hb.hb_blob_get_data(resultBlob, 0);
        const length = hb.hb_blob_get_length(resultBlob);
        if (!length) throw new Error("HarfBuzz returned an empty font subset");
        return new Uint8Array(new Uint8Array(hb.memory.buffer, offset, length));
      } finally {
        hb.hb_blob_destroy(resultBlob);
      }
    } finally {
      hb.hb_face_destroy(subsetFace);
    }
  } finally {
    hb.hb_subset_input_destroy(input);
    hb.hb_face_destroy(face);
    hb.free(fontPointer);
  }
}
