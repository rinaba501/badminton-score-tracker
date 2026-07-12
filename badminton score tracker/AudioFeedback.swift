//
//  AudioFeedback.swift
//  badminton score tracker (iOS)
//
//  Spoken score announcements (AVSpeechSynthesizer) and programmatic sine-wave
//  tones (AVAudioEngine). No audio files required. Per-target copy of the
//  Watch's — AVFoundation is cross-platform, so this is byte-for-byte the same
//  behaviour.
//

import AVFoundation
import Combine

final class ScoreAnnouncer: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.volume = 1.0
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        utterance.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

final class SoundPlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    // Force-unwrap is safe: a standard PCM format at a fixed 44.1 kHz / mono
    // is always constructible.
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private func tone(frequency: Float, duration: Float, amplitude: Float = 0.45) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(Float(sampleRate) * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        let sr = Float(sampleRate)
        let decaySamples = sr * duration * 0.4
        for i in 0..<Int(frames) {
            let env = exp(-Float(i) / decaySamples)
            data[i] = amplitude * env * sin(2 * .pi * frequency * Float(i) / sr)
        }
        return buf
    }

    private func schedule(_ buf: AVAudioPCMBuffer, after delay: Double = 0) {
        let block = {
            if !self.engine.isRunning { try? self.engine.start() }
            self.node.scheduleBuffer(buf)
            if !self.node.isPlaying { self.node.play() }
        }
        if delay == 0 { block() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) }
    }

    func playScore()     { schedule(tone(frequency: 880, duration: 0.18)) }
    func playGamePoint() { schedule(tone(frequency: 740, duration: 0.18)) }

    // Descending two-note "reversal" cue — mirror image of playScore's single
    // rising tone, so undo reads as the opposite action by ear alone.
    func playUndo() {
        schedule(tone(frequency: 660, duration: 0.12))
        schedule(tone(frequency: 440, duration: 0.14), after: 0.1)
    }

    func playGameWin() {
        schedule(tone(frequency: 523, duration: 0.2))
        schedule(tone(frequency: 659, duration: 0.25), after: 0.18)
    }

    func playMatchWin() {
        schedule(tone(frequency: 523, duration: 0.15))
        schedule(tone(frequency: 659, duration: 0.15), after: 0.15)
        schedule(tone(frequency: 784, duration: 0.35, amplitude: 0.6), after: 0.3)
    }
}
