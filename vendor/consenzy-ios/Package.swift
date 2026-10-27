// swift-tools-version:5.9
// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "OnFinanceConsenzy",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "OnFinanceConsenzy", targets: ["OnFinanceConsenzy"]),
        .library(name: "OnFinanceConsenzyUI", targets: ["OnFinanceConsenzyUI"]),
    ],
    targets: [
        // Foundation only. Builds and tests on Apple platforms and Linux.
        .target(
            name: "OnFinanceConsenzy",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // SwiftUI. Every file is wrapped in `#if canImport(SwiftUI)`, so on Linux this
        // target compiles to an empty module.
        .target(
            name: "OnFinanceConsenzyUI",
            dependencies: ["OnFinanceConsenzy"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // Vendored copy: the SDK's own test target is omitted because Tests/ is not vendored.
    ]
)
