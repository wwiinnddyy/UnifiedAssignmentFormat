declare module "subset-font" {
  export interface SubsetFontOptions {
    targetFormat?: "sfnt" | "truetype" | "woff" | "woff2";
    preserveNameIds?: number[];
    variationAxes?: Record<
      string,
      number | { min?: number; max?: number; default?: number }
    >;
    noLayoutClosure?: boolean;
  }

  export default function subsetFont(
    buffer: Uint8Array,
    text: string,
    options?: SubsetFontOptions,
  ): Promise<Uint8Array>;
}
