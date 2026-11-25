//
//  FileManager+documents.swift
//  ArcSign
//

import Foundation.NSFileManager

extension FileManager {
	/// Application workspace directory (`~/Library/Application Support/ArcSign` on macOS to avoid TCC ~/Documents prompts and clutter).
	var appWorkspaceDirectory: URL {
		#if os(macOS)
		let base = urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("ArcSign", isDirectory: true)
		if !fileExists(atPath: base.path) {
			try? createDirectory(at: base, withIntermediateDirectories: true)
		}
		return base
		#else
		return URL.documentsDirectory
		#endif
	}

	var archives: URL {
		appWorkspaceDirectory.appendingPathComponent("App").appendingPathComponent("Archives")
	}
	
	var signed: URL {
		appWorkspaceDirectory.appendingPathComponent("App").appendingPathComponent("Signed")
	}
	
	func signed(_ uuid: String) -> URL {
		signed.appendingPathComponent(uuid)
	}
	
	var unsigned: URL {
		appWorkspaceDirectory.appendingPathComponent("App").appendingPathComponent("Unsigned")
	}
	
	func unsigned(_ uuid: String) -> URL {
		unsigned.appendingPathComponent(uuid)
	}
	
	var certificates: URL {
		let certificatesDirectory = appWorkspaceDirectory.appendingPathComponent("Certificates")
		if !fileExists(atPath: certificatesDirectory.path) {
			try? createDirectory(at: certificatesDirectory, withIntermediateDirectories: true)
		}
		return certificatesDirectory
	}
	
	func certificates(_ uuid: String) -> URL {
		certificates.appendingPathComponent(uuid)
	}
	
	var tweaks: URL {
		appWorkspaceDirectory.appendingPathComponent("App").appendingPathComponent("Tweaks")
	}
}
