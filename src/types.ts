export type LineItem = { id: string; name: string; quantity: number; unitPrice: number; total: number; category: string };
export type Receipt = { id: string; fileName: string; merchant: string; date: string; currency: string; items: LineItem[]; subtotal: number; tax: number; discount: number; total: number; confidence: number; warnings: string[] };
