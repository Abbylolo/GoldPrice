# Repository guidance

GoldPrice is Abbylolo's native macOS menu-bar tracker, forked from Tespera/GoldPrice. Scope is CMB customer buy/sell gold-account prices and London spot XAU. Keep the interface in Simplified Chinese and preserve this narrow scope.

## Build

macOS 13+, Swift 6 toolchain, Swift 5 language mode. System frameworks only: AppKit, SwiftUI, Charts, Combine, ServiceManagement and UserNotifications.

```sh
swift test
swift run GoldPrice --preview --data-directory /tmp/goldprice-qa
bash scripts/build-app.sh
```

Bundle ID is `com.abbylolo.goldprice`; the app uses `LSUIElement=true`. The `--preview` option opens the same SwiftUI content in a normal window for development. Use a separate `--data-directory` for verification; never seed synthetic trades into a user's real data.

## Architecture

- `GoldPriceApp.swift`: application and notification delegate.
- `StatusBarController.swift`: status item, popover and development preview window.
- `GoldPriceView.swift`: market, holdings, alerts and preferences.
- `GoldPriceService.swift`: URLSession requests to CMB/Sina and XAU minutes; system curl for the large Eastmoney XAU daily response, cached daily.
- `AppStore.swift`: MainActor state, refresh, JSON persistence, alert delivery and login-item registration.
- `Sources/GoldPriceCore`: Foundation-only quote parsers, moving weighted-average portfolio and alert conditions.
- `Tests/GoldPriceCoreTests`: business-logic and parser tests; run these before changing cost or notification rules.

## Data rules

- `cmbBuy` is the customer's purchase price; `cmbSell` is the customer's selling price. Holdings are valued with `cmbSell` in CNY/gram.
- London XAU is spot gold in USD/troy ounce. Never substitute gold futures or relabel another instrument as XAU.
- CMB history is locally recorded actual observations. Do not invent past CMB prices or relabel another domestic series as CMB history.
- Keep provider timestamps and show stale quote states. Stale or explicitly closed-market quotes cannot fire alerts.
- Monetary calculations use Decimal. Buying includes explicit total fees; selling realizes profit and preserves remaining average cost. Reject historical overselling when adding or removing trades.
- A price rule fires once, is persisted as disabled after notification submission and can be re-enabled by the user.
- Corrupt local data must not be overwritten with a new empty portfolio.

The default data location is Application Support/GoldPricePersonal/state.json. Keep it separate from the original app's data and bundle identity.
