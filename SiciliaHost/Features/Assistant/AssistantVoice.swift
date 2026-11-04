import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Riconoscimento vocale (Speech-to-Text) e sintesi vocale (Text-to-Speech) nativi iOS.
@Observable
public final class AssistantVoice: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public var canListen: Bool = false
    public var canSpeak: Bool = true
    public var listening: Bool = false
    public var speaking: Bool = false
    public var interim: String = ""
    public var denied: Bool = false
    public var deniedPermanently: Bool = false
    public var failed: Bool = false

    private let locale: Locale
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let synthesizer = AVSpeechSynthesizer()
    private var onSpeechEnd: (() -> Void)?

    public init(locale: Locale = assistantLocale()) {
        self.locale = locale
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        self.canListen = speechRecognizer?.isAvailable ?? false
        self.synthesizer.delegate = self
    }

    public func markDenied(permanent: Bool) {
        denied = true
        deniedPermanently = permanent
    }

    public func clearDenied() {
        denied = false
        deniedPermanently = false
    }

    public func listen(onFinal: @escaping (String) -> Void) {
        guard canListen else {
            failed = true
            return
        }

        cancelListening()
        denied = false
        deniedPermanently = false
        failed = false
        interim = ""

        // Richiesta permessi microfono e riconoscimento vocale
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch status {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async {
                            if granted {
                                self.startRecording(onFinal: onFinal)
                            } else {
                                self.markDenied(permanent: true)
                            }
                        }
                    }
                case .denied, .restricted:
                    self.markDenied(permanent: true)
                case .notDetermined:
                    self.markDenied(permanent: false)
                @unknown default:
                    self.failed = true
                }
            }
        }
    }

    private func startRecording(onFinal: @escaping (String) -> Void) {
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result {
                    self.interim = result.bestTranscription.formattedString
                    if result.isFinal {
                        let finalStr = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.stopListening()
                        if !finalStr.isEmpty {
                            onFinal(finalStr)
                        }
                    }
                }
                if error != nil {
                    self.cancelListening()
                }
            }
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            listening = true
        } catch {
            failed = true
            cancelListening()
        }
    }

    public func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        listening = false
        interim = ""
    }

    public func cancelListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        listening = false
        interim = ""
    }

    // MARK: - Sintesi Vocale (Text-to-Speech)

    public func speak(_ text: String, onEnd: (() -> Void)? = nil) {
        stopSpeaking()
        let clean = speechText(text)
        guard !clean.isEmpty else {
            onEnd?()
            return
        }

        let utterance = AVSpeechUtterance(string: clean)
        let langCode = assistantLanguage(locale.language.languageCode?.identifier)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode == "it" ? "it-IT" : (langCode == "en" ? "en-GB" : "\(langCode)-\(langCode.uppercased())"))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        self.onSpeechEnd = onEnd
        self.speaking = true
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speaking = false
        onSpeechEnd = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speaking = false
            let callback = self.onSpeechEnd
            self.onSpeechEnd = nil
            callback?()
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speaking = false
            self.onSpeechEnd = nil
        }
    }
}
