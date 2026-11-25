//
//  VariedTabbarView.swift
//  Feather
//

import SwiftUI

struct VariedTabbarView: View {
	init() {}
	
	var body: some View {
		#if os(macOS)
		MacSidebarNavigationView()
		#else
		if #available(iOS 18, *) {
			ExtendedTabbarView()
		} else {
			TabbarView()
		}
		#endif
	}
}
