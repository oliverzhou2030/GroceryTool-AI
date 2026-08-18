import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import OpenAI from 'openai';
import { z } from 'zod';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024, files: 20 }, fileFilter: (_r, f, cb) => cb(null, f.mimetype.startsWith('image/') || f.mimetype === 'application/pdf') });
app.use(cors());
app.use(express.json());
const receiptSchema = z.object({
    merchant: z.string(), date: z.string(), currency: z.string().length(3),
    items: z.array(z.object({ name: z.string(), quantity: z.number(), unitPrice: z.number(), total: z.number(), category: z.string() })),
    subtotal: z.number(), tax: z.number(), discount: z.number(), total: z.number(), confidence: z.number().min(0).max(1), warnings: z.array(z.string())
});
const jsonSchema = { type: 'object', additionalProperties: false, required: ['merchant', 'date', 'currency', 'items', 'subtotal', 'tax', 'discount', 'total', 'confidence', 'warnings'], properties: {
        merchant: { type: 'string' }, date: { type: 'string' }, currency: { type: 'string' }, items: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'quantity', 'unitPrice', 'total', 'category'], properties: { name: { type: 'string' }, quantity: { type: 'number' }, unitPrice: { type: 'number' }, total: { type: 'number' }, category: { type: 'string' } } } }, subtotal: { type: 'number' }, tax: { type: 'number' }, discount: { type: 'number' }, total: { type: 'number' }, confidence: { type: 'number' }, warnings: { type: 'array', items: { type: 'string' } }
    } };
app.post('/api/receipts/scan', upload.array('receipts', 20), async (req, res) => {
    try {
        if (!process.env.OPENAI_API_KEY)
            return res.status(503).json({ error: 'OPENAI_API_KEY is not configured. Copy .env.example to .env and add your key.' });
        const files = req.files || [];
        if (!files.length)
            return res.status(400).json({ error: 'Add at least one image or PDF receipt.' });
        const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
        const receipts = await Promise.all(files.map(async (file) => {
            const dataUrl = `data:${file.mimetype};base64,${file.buffer.toString('base64')}`;
            const media = file.mimetype === 'application/pdf'
                ? { type: 'input_file', filename: file.originalname, file_data: dataUrl }
                : { type: 'input_image', image_url: dataUrl, detail: 'high' };
            const response = await client.responses.create({
                model: process.env.OPENAI_MODEL || 'gpt-5.6-sol',
                input: [{ role: 'user', content: [
                            { type: 'input_text', text: 'Extract this grocery receipt faithfully. Use YYYY-MM-DD when the date is legible, ISO 4217 currency, positive numbers, and grocery categories such as Produce, Dairy, Meat, Pantry, Frozen, Bakery, Beverages, Household, Personal care, or Other. Never invent unreadable values; use 0 or an empty string and explain uncertainty in warnings. Quantity defaults to 1 only when one line item is clearly present. discount is a positive amount. Verify item totals and receipt arithmetic. confidence is overall extraction confidence from 0 to 1.' }, media
                        ] }],
                text: { format: { type: 'json_schema', name: 'grocery_receipt', strict: true, schema: jsonSchema } }
            });
            const parsed = receiptSchema.parse(JSON.parse(response.output_text));
            return { ...parsed, id: crypto.randomUUID(), fileName: file.originalname, items: parsed.items.map(item => ({ ...item, id: crypto.randomUUID() })) };
        }));
        res.json({ receipts });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Receipt scanning failed.';
        res.status(500).json({ error: message });
    }
});
const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.resolve(here, '../dist');
app.use(express.static(dist));
app.use((_req, res) => res.sendFile(path.join(dist, 'index.html')));
app.listen(Number(process.env.PORT || 8787), () => console.log(`Market Ledger running on http://localhost:${process.env.PORT || 8787}`));
