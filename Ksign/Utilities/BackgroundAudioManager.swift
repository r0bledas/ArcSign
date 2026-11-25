//
//  BackgroundAudioManager.swift
//  Ksign
//

import Foundation
#if os(iOS)
import AVFoundation

class BackgroundAudioManager {
	static let shared = BackgroundAudioManager()
	private let _engine = AVAudioEngine()
	private init() {}

	func start() {
		guard OptionsManager.shared.options.backgroundAudio else { return }
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, options: [.mixWithOthers])
			try session.setActive(true)
			let silence = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
				let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
				for buffer in ablPointer {
					memset(buffer.mData, 0, Int(buffer.mDataByteSize))
				}
				return noErr
			}
			_engine.attach(silence)
			_engine.connect(silence, to: _engine.mainMixerNode, format: nil)
			try _engine.start()
		} catch {
			print("failed to start engine:", error)
		}
	}

	func stop() {
		_engine.stop()
		try? AVAudioSession.sharedInstance().setActive(false)
	}
}
#else
class BackgroundAudioManager {
	static let shared = BackgroundAudioManager()
	private init() {}
	func start() {}
	func stop() {}
}
#endif
