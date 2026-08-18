# Market Ledger

Market Ledger turns grocery receipt images or PDFs into an editable, consolidated bill. It extracts merchants, dates, line items, categories, quantities, prices, discounts, tax, and totals with OpenAI vision.

## Features

- Upload up to 20 receipt images or PDFs at once
- Structured receipt extraction with confidence and review warnings
- Edit, add, and remove every line item
- Consolidated subtotal, tax, discounts, and grand total
- Export a CSV or print/save the finished bill as PDF
- API keys stay on the server and uploaded files are processed in memory

## Run locally

Requires Node.js 20+ and an OpenAI API key.

```bash
npm install
cp .env.example .env
# Add your OPENAI_API_KEY to .env
npm run dev
```

Open http://localhost:5173. The API runs on port 8787.

## Production

```bash
npm run build
npm start
```

The server serves the built app from `dist/`. Set `PORT`, `OPENAI_API_KEY`, and optionally `OPENAI_MODEL` in your hosting environment.

## Privacy

Receipts are held in memory only long enough to send them for extraction. This starter does not include user accounts or persistent storage. Review extracted values before using them for reimbursement, accounting, or tax purposes.
