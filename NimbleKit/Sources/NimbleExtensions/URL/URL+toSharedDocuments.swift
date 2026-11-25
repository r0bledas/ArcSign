//
//  URL+toSharedDocuments.swift
//  Feather
//

import Foundation.NSURL

extension URL {
	/// Convert normal url to one that can be opened with files app (or Finder on macOS)
	public func toSharedDocumentsURL() -> URL? {
		#if os(macOS)
		return self
		#else
		let urlString = self.absoluteString
		guard urlString.hasPrefix("file://") else {
			return nil
		}
		let newURLString = "shareddocuments://" + urlString.dropFirst("file://".count)
		return URL(string: newURLString)
		#endif
	}
}
