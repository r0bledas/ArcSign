//
//  UIUserInterfaceStyle+cases.swift
//  Feather
//

import Foundation
#if canImport(UIKit)
import UIKit

extension UIUserInterfaceStyle: @retroactive CaseIterable {
	public static var allCases: [UIUserInterfaceStyle] {
		[.unspecified, .dark, .light]
	}
	
	var label: String {
		switch self {
		case .unspecified: .localized("Default")
		case .dark: .localized("Dark")
		case .light: .localized("Light")
		@unknown default: .localized("Unknown")
		}
	}
}
#elseif os(macOS)
import AppKit

public enum UIUserInterfaceStyle: Int, CaseIterable {
	case unspecified = 0
	case light = 1
	case dark = 2

	public static var allCases: [UIUserInterfaceStyle] {
		[.unspecified, .dark, .light]
	}

	var label: String {
		switch self {
		case .unspecified: .localized("Default")
		case .dark: .localized("Dark")
		case .light: .localized("Light")
		}
	}

	var nsAppearance: NSAppearance? {
		switch self {
		case .unspecified: return nil
		case .light: return NSAppearance(named: .aqua)
		case .dark: return NSAppearance(named: .darkAqua)
		}
	}
}
#endif
