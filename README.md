# Consenzy iOS example (Swift, SwiftUI)

[![CI](https://github.com/never2average/consenzy-example-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/never2average/consenzy-example-ios/actions/workflows/ci.yml)

An example iOS app for the [Consenzy](https://consenzy.onfinance.ai) DPDP consent SDK (`OnFinanceConsenzy` and
`OnFinanceConsenzyUI`). It shows the journeys a bank or fintech app needs under India's Digital Personal Data
Protection Act: consent collection, checking consent before using data, a preferences centre, Data Principal rights
requests, and guardian consent for a minor.

It runs with **zero setup**: the default in-app demo mode answers every call in memory with synthetic data, while the
real SDK code (request building, token handling, retries, idempotency keys, error decoding) runs unchanged over a fake
HTTP transport. Switch to the [example session server](https://github.com/never2average/consenzy-example-session-server)
to see the real token flow, or point that server at your own Consenzy organisation.

## Journeys

| # | Journey | What it shows | Source |
|---|---|---|---|
| 0 | Sign in, home, logout | Pick the backend mode and a demo customer; the backend mints a `cps_…` session; `me()` shows `acting_as` and capabilities; logout revokes the token | [`SignInView.swift`](App/Screens/SignInView.swift), [`HomeView.swift`](App/Screens/HomeView.swift), [`AppState.swift`](App/AppState.swift) |
| 1 | Consent collection | `currentNotice(language:)` in English / Hindi, and Tamil to show the English fallback; the itemised notice (title, body, each purpose with description, data categories, retention); purposes all off by default; `giveConsent(noticeId:purposeIds:idempotencyKey:)` for only the ticked purposes; the drop-in `ConsentSheet` | [`ConsentCollectionView.swift`](App/Screens/ConsentCollectionView.swift) |
| 2 | Check consent before use | "Send me offers" asks the backend (`POST /consent-check`, which calls `POST /v1/consents/check` with the org key) for `marketing` and proceeds only when `allowed`; shows `consent_id`, `ledger_event_id` and `ledger_hash` as evidence; fails closed on errors | [`ConsentCheckView.swift`](App/Screens/ConsentCheckView.swift), [`SessionServerClient.swift`](App/Backend/SessionServerClient.swift) |
| 3 | Preferences centre | `listConsents(activeOnly: true)`; Withdraw with a confirmation and optional reason via `withdrawConsent(id:reason:)`; the drop-in `ConsentManagerView` | [`PreferencesView.swift`](App/Screens/PreferencesView.swift) |
| 4 | Rights requests | `fileDataRequest(_:)` with typed `.access(AccessDetails)`, `.correction(CorrectionDetails)`, `.erasure(ErasureDetails)`, `.grievance(GrievanceDetails)`; status tracking with `listDataRequests()` (status, channel including the seeded request that arrived on WhatsApp, due date, refresh); the drop-in `RightsRequestForm` | [`RightsRequestsView.swift`](App/Screens/RightsRequestsView.swift) |
| 5 | Guardian consent and nominee | For the minor `CUST-DEMO-CHILD-7`: a `data_principal` session's grant is refused (`ConsentAPIError.isGuardianRequired`, DPDP s.9), then a guardian session (`acting_as=guardian`) records consent; a nominee via `.nomination(NominationDetails)` (s.14) | [`GuardianConsentView.swift`](App/Screens/GuardianConsentView.swift) |

Supporting code:

| What | Source |
|---|---|
| Session token provider: mint through the backend, build `ConsentSession(baseURL:sessionProvider:urlSession:)`, re-mint after a 401 | [`App/Backend/ConsentSessionFactory.swift`](App/Backend/ConsentSessionFactory.swift) |
| Client for the app's own backend (`/session`, `/consent-check`, `/demo-customers`) | [`App/Backend/SessionServerClient.swift`](App/Backend/SessionServerClient.swift) |
| In-app demo (demo only): fake transport and in-memory backend | [`App/Demo/DemoURLProtocol.swift`](App/Demo/DemoURLProtocol.swift), [`App/Demo/DemoBackend.swift`](App/Demo/DemoBackend.swift), [`App/Demo/DemoFixtures.swift`](App/Demo/DemoFixtures.swift), [`App/Resources/demo-fixtures.json`](App/Resources/demo-fixtures.json) |
| Unit tests for every journey | [`Tests/JourneyTests.swift`](Tests/JourneyTests.swift) |

## Run it

Requirements: macOS with Xcode 15 or later (iOS 16+ simulator) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The Xcode project is generated from [`project.yml`](project.yml) and is not committed.

```bash
brew install xcodegen
xcodegen generate
open ConsenzyExample.xcodeproj      # then Run on an iPhone simulator
```

From the command line:

```bash
xcodebuild test -project ConsenzyExample.xcodeproj -scheme ConsenzyExample \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

(Use any iPhone simulator from `xcrun simctl list devices available`.)

### Mode 1: in-app demo (default, no setup)

Launch the app, keep **In-app demo**, choose a customer and sign in:

- `CUST-DEMO-0001`, Asha, an adult with an erasure request that "arrived on WhatsApp".
- `CUST-DEMO-CHILD-7`, Kabir, 12, whose consent only a verified guardian can give.

Everything lives in memory and resets when the app is killed. Requests you file move from `received` to
`in_progress` after 20 seconds and to `completed` after 60 seconds, so the status tracking has something to show.

How it works: [`DemoURLProtocol`](App/Demo/DemoURLProtocol.swift) is a `URLProtocol` registered on a
`URLSessionConfiguration`. The app passes that `URLSession` to its backend client and, as `urlSession:`, to
`ConsentSession`. Requests to the demo host (`https://demo-….consenzy.invalid`) are answered by
[`DemoBackend`](App/Demo/DemoBackend.swift), a Swift port of the session server's `src/mock.js` using the same
[fixtures](App/Resources/demo-fixtures.json): notice in en/hi with English fallback, grant with supersede and
Idempotency-Key replay, withdraw, rights requests with validation and status progression, the guardian rule,
capabilities and logout. The whole `App/Demo` folder is demo-only; a real app deletes it.

### Mode 2: example session server

```bash
git clone https://github.com/never2average/consenzy-example-session-server
cd consenzy-example-session-server
npm ci && npm start                  # demo mode on http://localhost:8787
```

In the app choose **Session server**, keep `http://localhost:8787` (the simulator shares the Mac's localhost) and sign
in. The app now calls `POST /session` and `POST /consent-check` on the server, and the SDK talks to the `base_url` the
server returns (the server's own mock `/v1/me` API in demo mode).

The SDK accepts any base URL, but iOS App Transport Security blocks plain HTTP, so
[`Support/Info.plist`](Support/Info.plist) sets `NSAllowsLocalNetworking` only. That exception covers localhost and
local network names; everything else, including any real Consenzy deployment, must be HTTPS.

### Mode 3: a real Consenzy organisation

Run the session server in live mode (see its README): in the Consenzy portal register the app under
**Configuration → Applications**, issue the backend an API key with the `sessions:mint` and `consents:check` scopes,
create principals for the external references you want to test, and start the server with

```bash
CONSENZY_MODE=live
CONSENZY_BASE_URL=https://consenzy.onfinance.ai   # or your own deployment
CONSENZY_API_KEY=cdm_…                           # server-side only; never in the app
ALLOWED_EXTERNAL_REFS=CUST-0001,CUST-0002
```

The app needs no change: `/session` now returns a real `cps_…` token and `base_url` pointing at your deployment. On a
device, use an HTTPS URL for the session server.

## Architecture: no API keys in apps

```
 iOS app ──(your login)──▶ your backend ──(org key cdm_…, sessions:mint)──▶ Consenzy  POST /v1/principal-sessions
    │                          │◀────────────── cps_… token (≤ 1 h, one customer) ─────┘
    │◀──── cps_… + base_url ───┘
    │
    └──(OnFinanceConsenzy, Bearer cps_…)──▶ Consenzy  /v1/me/*   (notice, consents, rights requests)

 your backend ──(org key, consents:check)──▶ Consenzy  POST /v1/consents/check   (before using data for a purpose)
```

- The app holds no credentials. The organisation API key (`cdm_…`) stays on your backend; `ConsentSession` even
  rejects a `cdm_` token before sending anything (`ConsentClientError.organizationAPIKeyRejected`).
- The app gets a short-lived principal session token (`cps_…`) for the signed-in customer only. The SDK calls the
  `sessionProvider` closure when it first needs a token and once more after a 401
  ([`ConsentSessionFactory.swift`](App/Backend/ConsentSessionFactory.swift)).
- Consent checks before processing happen on the backend, which fails closed.
- In production your backend derives the customer from its own login. The example session server takes
  `external_ref` from the request (against an allow-list) only to keep the demo simple.

## Vendored SDK

The SDK is not yet published to Swift Package Manager or CocoaPods trunk, so a copy of its source (version 0.1.0,
Apache-2.0, Copyright 2026 OnFinance) is vendored in [`vendor/consenzy-ios`](vendor/consenzy-ios) and referenced as a
local Swift package in [`project.yml`](project.yml). See [`vendor/consenzy-ios/README.md`](vendor/consenzy-ios/README.md)
for how to switch to the registry dependency once it exists. The module names (`OnFinanceConsenzy`,
`OnFinanceConsenzyUI`) stay the same.

## CI

[GitHub Actions](.github/workflows/ci.yml) on `macos-latest` generates the project with XcodeGen, picks the first
available iPhone simulator, and runs `xcodebuild build` and `xcodebuild test` with code signing disabled.

## Licence

The example code is MIT licensed (see [LICENSE](LICENSE)). The vendored SDK in `vendor/consenzy-ios` is Apache-2.0
(see its [LICENSE](vendor/consenzy-ios/LICENSE) and [NOTICE](vendor/consenzy-ios/NOTICE)). The Consenzy server and API
are proprietary OnFinance software and are not part of this repository. All customer data in this repository is
synthetic.
