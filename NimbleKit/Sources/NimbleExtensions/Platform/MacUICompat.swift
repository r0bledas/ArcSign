//
//  MacUICompat.swift
//  NimbleExtensions
//

#if os(macOS)
import AppKit
import SwiftUI

public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIFont = NSFont
public typealias UIViewController = NSViewController
public typealias UIView = NSView

extension NSFont {
	public var lineHeight: CGFloat {
		ceil(ascender - descender + leading)
	}
}

extension Image {
	public init(uiImage: NSImage) {
		self.init(nsImage: uiImage)
	}
}

extension Color {
	public init(uiColor: NSColor) {
		self.init(nsColor: uiColor)
	}
}

extension NSImage {
	public var scale: CGFloat { 2.0 }

	public var cgImage: CGImage? {
		var rect = CGRect(origin: .zero, size: self.size)
		return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
	}

	public convenience init(cgImage: CGImage) {
		self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
	}

	public func pngData() -> Data? {
		guard let tiff = self.tiffRepresentation,
			  let rep = NSBitmapImageRep(data: tiff) else {
			return nil
		}
		return rep.representation(using: .png, properties: [:])
	}

	public func jpegData(compressionQuality: CGFloat) -> Data? {
		guard let tiff = self.tiffRepresentation,
			  let rep = NSBitmapImageRep(data: tiff) else {
			return nil
		}
		return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
	}
}

extension NSColor {
	public static var systemBackground: NSColor { .windowBackgroundColor }
	public static var secondarySystemBackground: NSColor { .controlBackgroundColor }
	public static var tertiarySystemBackground: NSColor { .underPageBackgroundColor }
	public static var systemGroupedBackground: NSColor { .windowBackgroundColor }
	public static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
	public static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
	public static var label: NSColor { .labelColor }
	public static var secondaryLabel: NSColor { .secondaryLabelColor }
	public static var tertiaryLabel: NSColor { .tertiaryLabelColor }
	public static var separator: NSColor { .separatorColor }
	public static var systemGray5: NSColor { NSColor.gray.withAlphaComponent(0.2) }
	public static var systemGray6: NSColor { NSColor.gray.withAlphaComponent(0.12) }
}

public final class UIPasteboard: @unchecked Sendable {
	public static let general = UIPasteboard()
	public var string: String? {
		get { NSPasteboard.general.string(forType: .string) }
		set {
			NSPasteboard.general.clearContents()
			if let newValue {
				NSPasteboard.general.setString(newValue, forType: .string)
			}
		}
	}
}

public final class UIImpactFeedbackGenerator {
	public enum FeedbackStyle { case light, medium, heavy, soft, rigid }
	public init(style: FeedbackStyle = .medium) {}
	public func prepare() {}
	public func impactOccurred() {}
}

public final class UINotificationFeedbackGenerator {
	public enum FeedbackType { case success, warning, error }
	public init() {}
	public func prepare() {}
	public func notificationOccurred(_ notificationType: FeedbackType) {}
}

public final class UIAlertAction {
	public enum Style {
		case `default`
		case cancel
		case destructive
	}

	public let title: String?
	public let style: Style
	public let handler: ((UIAlertAction) -> Void)?

	public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) {
		self.title = title
		self.style = style
		self.handler = handler
	}
}

public enum NavigationBarItem {
	public enum TitleDisplayMode {
		case automatic
		case inline
		case large
	}
}

public enum UIKeyboardType {
	case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad
}

public enum TextInputAutocapitalizationCompat {
	case never, words, sentences, characters
	public static var none: Self { .never }
}

public enum UIDeviceOrientation { case portrait }

public final class UIDevice: @unchecked Sendable {
	public enum UserInterfaceIdiom { case phone, pad, mac }
	public static let current = UIDevice()
	public var userInterfaceIdiom: UserInterfaceIdiom { .pad }
	public var systemVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }
	public var name: String { Host.current().localizedName ?? "Mac" }
}

public final class UIScreen: @unchecked Sendable {
	public static let main = UIScreen()
	public var bounds: CGRect { NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800) }
	public var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2.0 }
}

extension ToolbarItemPlacement {
	public static var topBarTrailing: ToolbarItemPlacement { .automatic }
	public static var topBarLeading: ToolbarItemPlacement { .navigation }
	public static var navigationBarTrailing: ToolbarItemPlacement { .automatic }
	public static var navigationBarLeading: ToolbarItemPlacement { .navigation }
	public static var bottomBar: ToolbarItemPlacement { .automatic }
}

public enum EditMode: Hashable, Sendable {
	case inactive
	case transient
	case active

	public var isEditing: Bool {
		self != .inactive
	}
}

private struct MacEditModeKey: EnvironmentKey {
	static let defaultValue: Binding<EditMode>? = nil
}

extension EnvironmentValues {
	public var editMode: Binding<EditMode>? {
		get { self[MacEditModeKey.self] }
		set { self[MacEditModeKey.self] = newValue }
	}
}

public struct EditButton: View {
	@Environment(\.editMode) private var editMode

	public init() {}

	public var body: some View {
		Button((editMode?.wrappedValue.isEditing ?? false) ? "Done" : "Select") {
			if let binding = editMode {
				binding.wrappedValue = binding.wrappedValue.isEditing ? .inactive : .active
			}
		}
	}
}

extension View {
	public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
		self
	}

	public func keyboardType(_ type: UIKeyboardType) -> some View {
		self
	}

	public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalizationCompat?) -> some View {
		self
	}

	public func autocapitalization(_ style: TextInputAutocapitalizationCompat) -> some View {
		self
	}

	public func fullScreenCover<Item: Identifiable, Content: View>(
		item: Binding<Item?>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping (Item) -> Content
	) -> some View {
		self.sheet(item: item, onDismiss: onDismiss, content: content)
	}

	public func fullScreenCover<Content: View>(
		isPresented: Binding<Bool>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
	}
}
#endif
