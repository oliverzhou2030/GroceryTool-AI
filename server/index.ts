import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import { z } from 'zod';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createWorker } from 'tesseract.js';
import { createCanvas } from '@napi-rs/canvas';

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024, files: 20 }, fileFilter: (_r, f, cb) => cb(null, f.mimetype.startsWith('image/') || f.mimetype === 'application/pdf') });
app.use(cors());
app.use(express.json());

const receiptSchema = z.object({
  merchant: z.string(), date: z.string(), currency: z.string().length(3),
  items: z.array(z.object({ name: z.string(), quantity: z.number(), unitPrice: z.number(), total: z.number(), category: z.string() })),
  subtotal: z.number(), tax: z.number(), discount: z.number(), total: z.number(), confidence: z.number().min(0).max(1), warnings: z.array(z.string())
});

async function readImage(buffer: Buffer) {
  const worker = await createWorker('eng');
  try {
    const result = await worker.recognize(buffer);
    return { text: result.data.text, confidence: result.data.confidence / 100 };
  } finally { await worker.terminate(); }
}

async function readReceipt(file: Express.Multer.File) {
  if (file.mimetype !== 'application/pdf') return readImage(file.buffer);
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const pdf = await pdfjs.getDocument({ data: new Uint8Array(file.buffer) }).promise;
  let text = ''; let confidence = 0;
  const pages = Math.min(pdf.numPages, 5);
  for (let pageNumber = 1; pageNumber <= pages; pageNumber++) {
    const page = await pdf.getPage(pageNumber);
    const native = await page.getTextContent();
    const nativeText = native.items.map(item => 'str' in item ? item.str : '').join(' ');
    if (nativeText.trim().length > 40) { text += `\n${nativeText}`; confidence += 0.95; continue; }
    const viewport = page.getViewport({ scale: 2 });
    const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
    await page.render({ canvas: canvas as never, canvasContext: canvas.getContext('2d') as never, viewport }).promise;
    const pageOcr = await readImage(canvas.toBuffer('image/png'));
    text += `\n${pageOcr.text}`; confidence += pageOcr.confidence;
  }
  return { text, confidence: confidence / pages };
}

app.post('/api/receipts/scan', upload.array('receipts', 20), async (req, res) => {
  try {
    if (!process.env.DEEPSEEK_API_KEY) return res.status(503).json({ error: 'DEEPSEEK_API_KEY is not configured. Copy .env.example to .env and add your complete key.' });
    const files = (req.files as Express.Multer.File[]) || [];
    if (!files.length) return res.status(400).json({ error: 'Add at least one image or PDF receipt.' });
    const receipts = await Promise.all(files.map(async (file) => {
      const ocr = await readReceipt(file);
      if (!ocr.text.trim()) throw new Error(`No readable text found in ${file.originalname}. Try a clearer, well-lit image.`);
      const prompt = `Convert the OCR text below into one grocery receipt. Return JSON only with exactly these fields: merchant string, date string (YYYY-MM-DD or empty), currency three-letter ISO code, items array of {name, quantity, unitPrice, total, category}, subtotal, tax, discount, total, confidence (0 to 1), warnings array of strings. Use positive numbers. Categories: Produce, Dairy, Meat, Pantry, Frozen, Bakery, Beverages, Household, Personal care, Other. Never invent missing values; use 0 or empty text and add a warning. Verify arithmetic. Limit confidence to at most ${ocr.confidence.toFixed(2)} because that is the OCR confidence.\n\nOCR TEXT:\n${ocr.text.slice(0, 50000)}`;
      const response = await fetch('https://api.deepseek.com/chat/completions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.DEEPSEEK_API_KEY}` },
        body: JSON.stringify({ model: process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash', messages: [{ role: 'user', content: prompt }], thinking: { type: 'disabled' }, response_format: { type: 'json_object' }, max_tokens: 5000 })
      });
      const result = await response.json() as { choices?: Array<{ message?: { content?: string } }>; error?: { message?: string } };
      if (!response.ok) throw new Error(result.error?.message || `DeepSeek returned ${response.status}`);
      const content = result.choices?.[0]?.message?.content;
      if (!content) throw new Error('DeepSeek returned an empty receipt.');
      const parsed = receiptSchema.parse(JSON.parse(content));
      return { ...parsed, id: crypto.randomUUID(), fileName: file.originalname, items: parsed.items.map(item => ({ ...item, id: crypto.randomUUID() })) };
    }));
    res.json({ receipts });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Receipt scanning failed.';
    res.status(500).json({ error: message });
  }
});

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.resolve(here, '../dist');
app.use(express.static(dist));
app.use((_req, res) => res.sendFile(path.join(dist, 'index.html')));
app.listen(Number(process.env.PORT || 8787), () => console.log(`Market Ledger running on http://localhost:${process.env.PORT || 8787}`));
