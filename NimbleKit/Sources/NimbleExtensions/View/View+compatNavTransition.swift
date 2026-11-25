//
//  View+NavTransition.swift
//  Luce
//

import SwiftUI

extension View {
	@ViewBuilder
	public func compatNavigationTransition(id: String, ns: Namespace.ID) -> some View {
		#if os(iOS)
		if #available(iOS 18.0, *) {
			self.navigationTransition(.zoom(sourceID: id, in: ns))
		} else {
			self
		}
		#else
		self
		#endif
	}
	
	@ViewBuilder
	public func compatMatchedTransitionSource(id: String, ns: Namespace.ID) -> some View {
		#if os(iOS)
		if #available(iOS 18.0, *) {
			self.matchedTransitionSource(id: id, in: ns)
		} else {
			self
		}
		#else
		self
		#endif
	}
}
