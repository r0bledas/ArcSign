//
//  PlatformExports.swift
//  ArcSign
//
//  Re-exports cross-platform AppKit/SwiftUI compatibility types across the macOS target.
//

@_exported import NimbleExtensions
#if os(macOS)
@_exported import AppKit
#endif
