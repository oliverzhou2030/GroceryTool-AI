# GroceryTool AI — SwiftUI

A native iPhone and Mac grocery assistant that turns receipt photos into clean bills, tracks spending, exports spreadsheet-ready records, compares multi-store shopping plans, recommends nearby substitutes, and learns store preferences on-device.

## Features

- Apple Vision OCR for receipt photos
- Multi-receipt imports create one independent history entry per photo or PDF
- Automatic receipt orientation, merchant, and purchase-date recognition
- Private on-device receipt history with PDF and Original views
- Softly whitened, straightened receipt scans and exportable clean PDFs containing parsed details
- Editable clean bills with categorized line items
- Product-aware default categories plus editable quantity/category fields
- Persistent category learning from user corrections
- Local JSON receipt history and preference learning
- Date-range analytics: total spend, food-to-snack ratio, and store ratios
- Item-count analytics grouped by grocery category
- Colorful bar and pie chart modes for food types and market spending
- Food-category spending ratios with both bar and pie chart views
- Receipt calendar with per-day history and custom date-range spending totals
- Multi-date calendar selection with tap-again deselection and selected-day totals
- UTF-8 CSV export for Microsoft Excel and Google Sheets
- One-store and two-store shopping plans with price, travel time, pros, and cons
- Real nearby grocery-store names and addresses from Open Prices location data
- Searchable store catalogs with crowdsourced prices from the last 180 days and last-observed dates
- Current Trader Joe's catalog prices through OpenPriceEngine when a local API key is configured
- Similar-product recommendations when a requested brand is unavailable nearby
- iPhone location permission flow for nearby-store comparisons
- Local account creation and sign-in, with a seeded `admin` / `admin` demo account
- White and light-blue design with System, Light, and Dark appearance modes
- In-app language switching between English, Simplified Chinese, and Spanish
- Shop star ratings and written reviews that influence recommendations
- Responsive SwiftUI interface for iPhone and Mac

## Open and run

1. Open `GroceryToolAI/GroceryToolAI.xcodeproj` in Xcode 26 or newer.
2. Select `GroceryToolAI` and choose My Mac or an iPhone simulator.
3. Press Run.

Or run the iPhone simulator directly from Terminal:

```sh
cd ~/Documents/GroceryTool-AI
./run-iphone.command
```

Run the native Mac app directly from Terminal:

```sh
cd ~/Documents/GroceryTool-AI
./run-mac.command
```

The launcher sets the Simulator location to `40.789, -73.702` each time it runs. To use another simulated coordinate:

```sh
GROCERYTOOL_LATITUDE=40.789 GROCERYTOOL_LONGITUDE=-73.702 ./run-iphone.command
```

On first sign-in, allow current-location access to enter the iPhone app. For development, use username `admin` and password `admin`. This is a local demo account; replace it with backend authentication before releasing the app.

Receipt history starts empty. Choose receipt images from Photos, import an image/PDF from Files, or enter a receipt manually. Select any saved receipt to inspect its clean bill, and swipe it or use the trash button to delete it.

In Calendar, tap as many dates as needed; tapping a selected date again removes it from the selection. In Insights, choose **Export CSV for Sheets** and share it to Google Drive/Google Sheets on iPhone, or import the saved CSV at Google Sheets on Mac.

The Shop tab reads the public Open Prices / Open Food Facts API without an API key. Its prices are crowdsourced observations from the last 180 days and therefore include a “last seen” date; they must not be treated as guaranteed live shelf inventory. Repeated chain locations are reduced to the closest store.

To enable OpenPriceEngine, put the key on a single line in `.openpricengine-key` at the repository root. The launcher passes it only to the Simulator app process; the file is ignored by Git. The free OpenPriceEngine plan currently exposes one U.S. grocery catalog (Trader Joe's), so nearby-shop location and routing still come from Apple MapKit and Open Prices.

## External APIs needed for live inventory

- Open Prices / Open Food Facts supplies free crowdsourced product, location, and observed-price data. Read requests require no account, but coverage varies by store.
- A retailer product/inventory API (for example Kroger Developer APIs, Walmart Marketplace APIs when eligible, or another licensed catalog provider).
- Apple MapKit can provide nearby-store search and routing after enabling the location capability; it does not provide product inventory.
- An optional LLM API can improve noisy OCR parsing, but the included cleaner works offline and sends no receipt data to third parties.

Never commit API keys. Store production credentials in Keychain or retrieve short-lived tokens from a backend.
