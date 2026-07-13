import { writeFile } from "node:fs/promises";
import { createUafPdf } from "../dist/index.js";

const document = [
  { subject: "Math", date: "2026-07-11", content: "Exercises 1, 2, and 3\nRead chapter 4 carefully.", tags: ["required", "homework"] },
  { subject: "English", date: "2026-07-11", content: "Read Unit 3 and finish the workbook pages.", tags: ["reading"] },
  { subject: "Science", date: "2026-07-11", content: "Lab notes preparation.\nBring safety goggles.\nWrite hypothesis.", tags: ["lab"] },
  { subject: "History", date: "2026-07-11", content: "Review the timeline for the upcoming quiz.", tags: [] },
];

const bytes = await createUafPdf(document, { useStandardFont: true, theme: "classworks-dark" });
await writeFile("sample-md3-dark.pdf", bytes);
console.log("Generated sample-md3-dark.pdf");
