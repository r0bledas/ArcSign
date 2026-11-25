//
//  Server+Compute.swift
//  feather
//

import Foundation
#if canImport(UIKit)
import UIKit.UIGraphicsImageRenderer
#elseif os(macOS)
import AppKit
#endif

extension ServerInstaller {
	var plistEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).plist"
		comps.port = port
		return comps.url!
	}

	var payloadEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/\(id).ipa"
		comps.port = port
		return comps.url!
	}
	
	var pageEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = ServerInstaller.getServerMethod() == 1 ? "http" : "https"
		comps.host = Self.sni
		comps.path = "/install"
		comps.port = port
		return comps.url!
	}
	
	var externalServerLink: String {
		let baseUrl = "https://api.palera.in/genPlist?bundleid=\(app.identifier!)&name=\(app.name!)&version=\(app.version!)&fetchurl=\(self.payloadEndpoint.absoluteString)"
		let encodedBaseUrl = baseUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		let finalEncodedUrl = encodedBaseUrl.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
		return finalEncodedUrl
	}

	var iTunesLink: String {
		_iTunesLink(with: plistEndpoint.absoluteString)
	}
	
	var iTunesLinkExternal: String {
		_iTunesLink(with: externalServerLink)
	}
	
	private func _iTunesLink(with url: String) -> String {
		return "itms-services://?action=download-manifest&url=\(url)"
	}

	var displayImageSmallEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app57x57.png"
		comps.port = port
		return comps.url!
	}

	var displayImageLargeEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = Self.sni
		comps.path = "/app512x512.png"
		comps.port = port
		return comps.url!
	}
	
	var displayImageSmallData: Data {
		_createIcon(57)
	}
	
	var displayImageLargeData: Data {
		_createIcon(512)
	}
	
	private func _createIcon(_ r: CGFloat) -> Data {
		#if canImport(UIKit)
		let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
		let image = renderer.image { ctx in
			UIColor.accent.setFill()
			ctx.fill(.init(x: 0, y: 0, width: r, height: r))
		}
		return image.pngData()!
		#else
		let img = NSImage(size: NSSize(width: r, height: r))
		img.lockFocus()
		NSColor.controlAccentColor.setFill()
		NSBezierPath(rect: NSRect(x: 0, y: 0, width: r, height: r)).fill()
		img.unlockFocus()
		return img.pngData() ?? Data()
		#endif
	}

	var html: String {
		"""
		<html style="background-color: black;">
		<script type="text/javascript">window.location="\(iTunesLinkExternal)"</script>
		</html>
		"""
	}

	var installManifest: [String: Any] {[
		"items": [[
			"assets": [
				[
					"kind": "software-package",
					"url": payloadEndpoint.absoluteString,
				],
				[
					"kind": "display-image",
					"url": "https://raw.githubusercontent.com/Nyasami/Ksign/refs/heads/main/Ksign/Resources/Assets.xcassets/AppIcons/AppIcon.appiconset/Ksign-default.png",
				],
			],
			"metadata": [
				"bundle-identifier": app.identifier as Any,
				"bundle-version": app.version as Any,
				"kind": "software",
				"title": app.name as Any,
			],
		],],
	]}

	var installManifestData: Data {
		(try? PropertyListSerialization.data(
			fromPropertyList: installManifest,
			format: .xml,
			options: .zero
		)) ?? .init()
	}
}
