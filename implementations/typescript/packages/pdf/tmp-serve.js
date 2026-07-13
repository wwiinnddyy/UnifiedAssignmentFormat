import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";

const MIME = {
  ".pdf": "application/pdf",
  ".js": "application/javascript",
  ".mjs": "application/javascript",
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host}`);
  const pathname = url.pathname === "/" ? "/sample-md3-dark.pdf" : url.pathname;
  const filePath = resolve(process.cwd(), "." + pathname);
  try {
    const data = await readFile(filePath);
    res.writeHead(200, { "Content-Type": MIME[extname(filePath)] || "application/octet-stream" });
    res.end(data);
  } catch (error) {
    res.writeHead(404);
    res.end(String(error));
  }
});

server.listen(8765, () => console.log("Serving PDF at http://localhost:8765/sample-md3-dark.pdf"));
