//
//  ServerInstaller.swift
//  ArcSign (Lightweight Network.framework LAN OTA Server — replaces 25-package Vapor stack)
//

import Foundation
import Network
import SwiftUI
import IDeviceSwift

class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _listener: NWListener?

	var packageUrl: URL?
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel
		try _startListener()
	}

	deinit {
		_shutdownServer()
	}

	private func _startListener() throws {
		guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
		let listener = try NWListener(using: .tcp, on: nwPort)
		listener.newConnectionHandler = { [weak self] conn in
			self?._handleConnection(conn)
		}
		listener.start(queue: .global(qos: .userInitiated))
		self._listener = listener
	}

	private func _handleConnection(_ connection: NWConnection) {
		connection.start(queue: .global(qos: .userInitiated))
		connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
			guard let self, let data, let reqStr = String(data: data, encoding: .utf8) else {
				connection.cancel()
				return
			}
			let firstLine = reqStr.components(separatedBy: "\r\n").first ?? ""
			let parts = firstLine.components(separatedBy: " ")
			let path = parts.count > 1 ? parts[1] : "/"

			switch path {
			case self.plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				self._sendHTTP(connection, contentType: "text/xml", body: self.installManifestData)
			case self.displayImageSmallEndpoint.path:
				self._sendHTTP(connection, contentType: "image/png", body: self.displayImageSmallData)
			case self.displayImageLargeEndpoint.path:
				self._sendHTTP(connection, contentType: "image/png", body: self.displayImageLargeData)
			case self.payloadEndpoint.path:
				guard let packageUrl = self.packageUrl, let ipaData = try? Data(contentsOf: packageUrl) else {
					self._sendNotFound(connection)
					return
				}
				self._updateStatus(.sendingPayload)
				self._sendHTTP(connection, contentType: "application/octet-stream", body: ipaData) {
					self._updateStatus(.installing)
				}
			case "/install":
				self._sendHTTP(connection, contentType: "text/html; charset=utf-8", body: Data(self.html.utf8))
			default:
				self._sendNotFound(connection)
			}
		}
	}

	private func _sendHTTP(_ conn: NWConnection, contentType: String, body: Data, completion: (() -> Void)? = nil) {
		let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
		var payload = Data(header.utf8)
		payload.append(body)
		conn.send(content: payload, completion: .contentProcessed { _ in
			completion?()
			conn.cancel()
		})
	}

	private func _sendNotFound(_ conn: NWConnection) {
		let resp = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
		conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
	}

	private func _shutdownServer() {
		_listener?.cancel()
		_listener = nil
	}

	private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}

	static func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}

	static func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}

	static func setServerMethod(_ method: Int) {
		UserDefaults.standard.set(method, forKey: "Feather.serverMethod")
	}

	static func setIPFix(_ enabled: Bool) {
		UserDefaults.standard.set(enabled, forKey: "Feather.ipFix")
	}
}
