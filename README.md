# Zara iOS Price Monitor

A standalone iOS application to monitor Zara product prices locally.

## Setup Instructions

1. **Create a New Xcode Project**:
   - Open Xcode and create a new "App" project.
   - Interface: SwiftUI
   - Language: Swift
   - Storage: SwiftData
   - Name: `ZaraMonitor` (or similar)

2. **Copy Files**:
   - Copy all the `.swift` files from this folder into your new Xcode project's main group.
   - Replace the default `ZaraMonitorApp.swift` (or `YourAppNameApp.swift`) with the one provided here.
   - Ensuring `ContentView.swift` and `Product.swift` (Item) are replaced or merged.

3. **Configure Capabilities** (Important for Background Tasks):
   - Go to your Project Target settings -> **Signing & Capabilities**.
   - Click `+ Capability`.
   - Add **Background Modes**.
   - Check **Background fetch**.
   - Check **Background processing**.
   
4. **Info.plist Setup**:
   - Add a new key: `Permitted background task scheduler identifiers`.
   - Add an item to this array: `com.zara.monitor.refresh` (This matches the ID in `BackgroundManager.swift`).

5. **Run**:
   - Build and run on a Simulator or Device.
   - **Note**: Background App Refresh works best on a real device and is subject to iOS optimization (it may not run exactly every hour).

## Features

- **Add Product**: Paste a Zara URL to fetch product details.
- **Monitoring**: Checks for price changes.
- **Notifications**: Sends a local notification if the price drops.
- **History**: Tracks price history over time.

## Limitations

- **Zara Anti-Bot**: Zara may block frequent requests or specific user agents. The scraper uses a mocked User-Agent, but this is not guaranteed to work forever.
- **Background Execution**: iOS determines when to run background tasks. It is not real-time.
