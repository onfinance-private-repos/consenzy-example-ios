# Vendored Consenzy iOS SDK

Vendored copy of the Consenzy iOS SDK (Apache-2.0, Copyright 2026 OnFinance) from version 0.1.0 (including the
unreleased `DataRequest.channel` / `channelReference` addition listed in the SDK changelog). Temporary until the SDK is
published to Swift Package Manager / CocoaPods (OnFinanceConsenzy); switch to the registry dependency then.

What is here:

| Path | Notes |
|---|---|
| `Sources/OnFinanceConsenzy`, `Sources/OnFinanceConsenzyUI` | Unmodified SDK source |
| `Package.swift` | Unmodified except that the SDK's test target is removed, because the SDK's `Tests/` folder is not vendored |
| `LICENSE`, `NOTICE` | Apache License 2.0 and the SDK's NOTICE, which apply to everything in this folder |

The rest of this repository is MIT licensed (see the top-level `LICENSE`); this folder stays Apache-2.0.

To switch to the published package later, remove this folder, delete the `packages.OnFinanceConsenzy.path` entry in
`project.yml`, and add the CocoaPods pods (`pod 'OnFinanceConsenzy', '~> 0.1'`, `pod 'OnFinanceConsenzyUI', '~> 0.1'`)
or the Swift Package URL once one exists. The module names (`OnFinanceConsenzy`, `OnFinanceConsenzyUI`) stay the same.
