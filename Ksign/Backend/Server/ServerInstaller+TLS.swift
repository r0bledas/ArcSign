//
//  Server+TLS.swift
//  ArcSign
//

import Foundation

extension ServerInstaller {
	static var sni: String {
		let localhost = "127.0.0.1"
		if getServerMethod() == 1 {
			return !ServerInstaller.getIPFix() ? (getLocalAddress() ?? localhost) : localhost
		} else {
			return readCommonName() ?? getLocalAddress() ?? localhost
		}
	}

	static func readCommonName() -> String? {
		guard let url = getUrl("commonName", ext: "txt") else { return nil }
		return try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default
		let base = fileManager.appWorkspaceDirectory
		let serverURL = base.appendingPathComponent("App").appendingPathComponent("Server").appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: serverURL.path) { return serverURL }
		let documentsURL = base.appendingPathComponent("\(name).\(ext)")
		if fileManager.fileExists(atPath: documentsURL.path) { return documentsURL }
		return Bundle.main.url(forResource: name, withExtension: ext)
	}

	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				defer { ptr = ptr!.pointee.ifa_next }
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				if addrFamily == UInt8(AF_INET) {
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "en1" {
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						getnameinfo(
							interface.ifa_addr,
							socklen_t(interface.ifa_addr.pointee.sa_len),
							&hostname,
							socklen_t(hostname.count),
							nil,
							socklen_t(0),
							NI_NUMERICHOST
						)
						address = String(cString: hostname)
					}
				}
			}
			freeifaddrs(ifaddr)
		}
		return address
	}
}
