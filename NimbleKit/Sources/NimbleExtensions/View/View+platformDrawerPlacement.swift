//
//  View+platformDrawerPlacement.swift
//  NimbleKit
//

import SwiftUI

extension SearchFieldPlacement {
	@MainActor public static func platform() -> SearchFieldPlacement {
		#if os(iOS)
		UIDevice.current.userInterfaceIdiom == .pad ? .automatic : .navigationBarDrawer(displayMode: .always)
		#else
		.automatic
		#endif
	}
}
