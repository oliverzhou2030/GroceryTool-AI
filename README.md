# GroceryTool AI — SwiftUI

A native iPhone and Mac grocery assistant that turns receipt photos into clean bills, tracks spending, exports spreadsheet-ready records, compares multi-store shopping plans, recommends nearby substitutes, and learns store preferences on-device.

## Features

- Apple Vision OCR for receipt photos
- Editable clean bills with categorized line items
- Local JSON receipt history and preference learning
- Date-range analytics: total spend, food-to-snack ratio, and store ratios
- UTF-8 CSV export for Microsoft Excel and Google Sheets
- One-store and two-store shopping plans with price, travel time, pros, and cons
- Similar-product recommendations when a requested brand is unavailable nearby
- iPhone location permission flow for nearby-store comparisons
- Local account creation and sign-in, with a seeded `admin` / `admin` demo account
- White and light-blue design with System, Light, and Dark appearance modes
- Shop star ratings and written reviews that influence recommendations
- Responsive SwiftUI interface for iPhone and Mac

## Open and run

1. Open `GroceryToolAI/GroceryToolAI.xcodeproj` in Xcode 26 or newer.
2. Select `GroceryToolAI` and choose My Mac or an iPhone simulator.
3. Press Run.

On first sign-in, allow current-location access to enter the iPhone app. For development, use username `admin` and password `admin`. This is a local demo account; replace it with backend authentication before releasing the app.

The sample store catalog is local and editable in `AppStore.swift`. Real-time retailer inventory requires retailer-specific APIs; see **External APIs**.

## External APIs needed for live inventory

- A retailer product/inventory API (for example Kroger Developer APIs, Walmart Marketplace APIs when eligible, or another licensed catalog provider).
- Apple MapKit can provide nearby-store search and routing after enabling the location capability; it does not provide product inventory.
- An optional LLM API can improve noisy OCR parsing, but the included cleaner works offline and sends no receipt data to third parties.

Never commit API keys. Store production credentials in Keychain or retrieve short-lived tokens from a backend.
