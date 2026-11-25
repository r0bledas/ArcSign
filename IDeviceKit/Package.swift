// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "IDeviceKit",
	platforms: [
		.iOS(.v15),
		.macOS(.v14),
	],
	products: [
		.library(
			name: "IDeviceSwift",
			targets: ["IDeviceSwift"]
		),
	],
	targets: [
		.target(
			name: "IDeviceSwift",
			path: "Sources/IDeviceSwift"
		),
	]
)
