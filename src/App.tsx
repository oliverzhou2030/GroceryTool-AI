import { useMemo, useRef, useState } from 'react';
import { Camera, ChevronDown, Download, FileText, Leaf, LoaderCircle, Plus, Printer, ReceiptText, RotateCcw, ShieldCheck, Sparkles, Trash2, Upload } from 'lucide-react';
import type { LineItem, Receipt } from './types';

const money = (n:number, currency='USD') => new Intl.NumberFormat(undefined,{style:'currency',currency:currency || 'USD'}).format(Number.isFinite(n)?n:0);
const blankItem = ():LineItem => ({id:crypto.randomUUID(),name:'New item',quantity:1,unitPrice:0,total:0,category:'Other'});

export default function App(){
  const input=useRef<HTMLInputElement>(null); const [files,setFiles]=useState<File[]>([]); const [receipts,setReceipts]=useState<Receipt[]>([]); const [selected,setSelected]=useState(0); const [busy,setBusy]=useState(false); const [error,setError]=useState(''); const [drag,setDrag]=useState(false);
  const current=receipts[selected];
  const totals=useMemo(()=>receipts.reduce((a,r)=>({items:a.items+r.items.length,subtotal:a.subtotal+r.subtotal,tax:a.tax+r.tax,discount:a.discount+r.discount,total:a.total+r.total}),{items:0,subtotal:0,tax:0,discount:0,total:0}),[receipts]);
  const choose=(incoming:FileList|File[])=>{const next=[...Array.from(incoming)].filter(f=>f.type.startsWith('image/')||f.type==='application/pdf');setFiles(old=>[...old,...next].slice(0,20));setError('')};
  const scan=async()=>{if(!files.length)return;setBusy(true);setError('');try{const form=new FormData();files.forEach(f=>form.append('receipts',f));const response=await fetch('/api/receipts/scan',{method:'POST',body:form});const data=await response.json();if(!response.ok)throw new Error(data.error||'Could not scan receipts');setReceipts(data.receipts);setSelected(0)}catch(e){setError(e instanceof Error?e.message:'Could not scan receipts')}finally{setBusy(false)}};
  const patchReceipt=(patch:Partial<Receipt>)=>setReceipts(all=>all.map((r,i)=>i===selected?{...r,...patch}:r));
  const patchItem=(id:string,patch:Partial<LineItem>)=>{if(!current)return;const items=current.items.map(x=>x.id===id?{...x,...patch}:x);patchReceipt({items,subtotal:items.reduce((s,x)=>s+x.total,0)});};
  const csv=()=>{const rows=[['Receipt','Merchant','Date','Item','Category','Quantity','Unit price','Line total','Currency'],...receipts.flatMap(r=>r.items.map(i=>[r.fileName,r.merchant,r.date,i.name,i.category,i.quantity,i.unitPrice,i.total,r.currency]))];const blob=new Blob([rows.map(row=>row.map(v=>`"${String(v).replaceAll('"','""')}"`).join(',')).join('\n')],{type:'text/csv'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='grocery-bill.csv';a.click();URL.revokeObjectURL(a.href)};
  return <div className="shell">
    <header><a className="brand"><span><Leaf size={20}/></span> MARKET LEDGER</a><div className="header-actions"><button className="ghost" onClick={()=>window.print()} disabled={!receipts.length}><Printer size={17}/> Print</button><button className="dark" onClick={csv} disabled={!receipts.length}><Download size={17}/> Export CSV</button></div></header>
    <main>
      {!receipts.length?<>
        <section className="hero"><div className="eyebrow"><Sparkles size={14}/> RECEIPTS, RECONCILED</div><h1>Turn grocery receipts<br/>into a <em>clean bill.</em></h1><p>Upload photos or PDFs. Market Ledger reads every line, organizes your groceries, and builds one tidy, editable bill.</p></section>
        <section className={`drop ${drag?'drag':''}`} onDragOver={e=>{e.preventDefault();setDrag(true)}} onDragLeave={()=>setDrag(false)} onDrop={e=>{e.preventDefault();setDrag(false);choose(e.dataTransfer.files)}} onClick={()=>input.current?.click()}>
          <input ref={input} type="file" multiple accept="image/*,.pdf" onChange={e=>e.target.files&&choose(e.target.files)}/><div className="upload-icon"><Upload size={25}/></div><h2>Drop your receipts here</h2><p>or click to browse · JPG, PNG, HEIC, WEBP, PDF · up to 20 files</p><button className="outline"><Camera size={17}/> Choose receipts</button>
        </section>
        {files.length>0&&<section className="queue"><div><strong>{files.length} receipt{files.length>1?'s':''} ready</strong><span>{files.map(f=>f.name).join(' · ')}</span></div><button className="dark scan" onClick={e=>{e.stopPropagation();scan()}} disabled={busy}>{busy?<LoaderCircle className="spin" size={18}/>:<Sparkles size={18}/>} {busy?'Reading receipts…':'Build my bill'}</button></section>}
        {error&&<div className="error">{error}</div>}
        <div className="trust"><span><ShieldCheck/>Your key stays on your server</span><span><ReceiptText/>Item-by-item extraction</span><span><FileText/>Printable, editable results</span></div>
      </>:<section className="workspace">
        <div className="workspace-head"><div><div className="eyebrow">YOUR GROCERY BILL</div><h1>{receipts.length} receipt{receipts.length>1?'s':''}, one clear total.</h1></div><button className="ghost" onClick={()=>{setReceipts([]);setFiles([])}}><RotateCcw size={16}/> Start over</button></div>
        <div className="summary"><div><span>LINE ITEMS</span><b>{totals.items}</b></div><div><span>SUBTOTAL</span><b>{money(totals.subtotal,current?.currency)}</b></div><div><span>TAX</span><b>{money(totals.tax,current?.currency)}</b></div><div className="grand"><span>GRAND TOTAL</span><b>{money(totals.total,current?.currency)}</b></div></div>
        <div className="ledger">
          <aside><h3>Receipts</h3>{receipts.map((r,i)=><button className={i===selected?'active':''} onClick={()=>setSelected(i)} key={r.id}><ReceiptText/><span><strong>{r.merchant||r.fileName}</strong><small>{r.date||'Date unknown'} · {r.items.length} items</small></span><b>{money(r.total,r.currency)}</b></button>)}</aside>
          {current&&<article className="bill"><div className="bill-head"><div><input className="merchant" value={current.merchant} onChange={e=>patchReceipt({merchant:e.target.value})}/><input className="date" type="date" value={current.date} onChange={e=>patchReceipt({date:e.target.value})}/></div><div className="confidence">{Math.round(current.confidence*100)}% confidence</div></div>
            {current.warnings.length>0&&<div className="warning">Review: {current.warnings.join(' ')}</div>}
            <div className="table"><div className="tr th"><span>Item</span><span>Category</span><span>Qty</span><span>Price</span><span>Total</span><span></span></div>{current.items.map(item=><div className="tr" key={item.id}><input value={item.name} onChange={e=>patchItem(item.id,{name:e.target.value})}/><div className="select"><input value={item.category} onChange={e=>patchItem(item.id,{category:e.target.value})}/><ChevronDown/></div><input type="number" min="0" step="0.01" value={item.quantity} onChange={e=>{const q=+e.target.value;patchItem(item.id,{quantity:q,total:q*item.unitPrice})}}/><input type="number" min="0" step="0.01" value={item.unitPrice} onChange={e=>{const p=+e.target.value;patchItem(item.id,{unitPrice:p,total:p*item.quantity})}}/><strong>{money(item.total,current.currency)}</strong><button aria-label="Remove item" onClick={()=>patchReceipt({items:current.items.filter(x=>x.id!==item.id)})}><Trash2/></button></div>)}</div>
            <button className="add" onClick={()=>patchReceipt({items:[...current.items,blankItem()]})}><Plus/> Add item</button>
            <div className="totals"><label><span>Subtotal</span><input type="number" value={current.subtotal} onChange={e=>patchReceipt({subtotal:+e.target.value})}/></label><label><span>Discount</span><input type="number" value={current.discount} onChange={e=>patchReceipt({discount:+e.target.value})}/></label><label><span>Tax</span><input type="number" value={current.tax} onChange={e=>patchReceipt({tax:+e.target.value})}/></label><label className="total"><span>Total</span><input type="number" value={current.total} onChange={e=>patchReceipt({total:+e.target.value})}/></label></div>
          </article>}
        </div>
      </section>}
    </main><footer>Built for clearer grocery spending <Leaf size={14}/></footer>
  </div>
}
