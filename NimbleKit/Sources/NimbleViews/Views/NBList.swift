//
//  NBList.swift
//  NimbleKit
//

import SwiftUI
import NimbleExtensions

public struct NBList<Content>: View where Content: View {
	public enum NBListType {
		case list
		case form
	}
	
	private var _title: String
	private var _mode: NavigationBarItem.TitleDisplayMode
	private var _type: NBListType
	private var _content: Content
	
	public init(
		_ title: String,
		displayMode: NavigationBarItem.TitleDisplayMode = .inline,
		type: NBListType = .form,
		@ViewBuilder content: () -> Content
	) {
		self._title = title
		self._mode = displayMode
		self._type = type
		self._content = content()
	}
	
	public var body: some View {
		Group {
			switch _type {
			case .form:
				Form {
					_content
				}
				#if os(macOS)
				.formStyle(.grouped)
				#endif
			case .list:
				List {
					_content
				}
			}
		}
		.navigationTitle(_title)
		#if os(iOS)
		.navigationBarTitleDisplayMode(_mode)
		#endif
	}
}
