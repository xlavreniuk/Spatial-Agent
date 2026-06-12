//
//  VoiceManager.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import AVFoundation
import Combine
import Speech

final class VoiceManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var authorizationMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioApplication.requestRecordPermission { microphoneAllowed in
                DispatchQueue.main.async {
                    guard let self else { return }

                    if speechStatus != .authorized {
                        self.authorizationMessage = "Speech recognition permission is required."
                    } else if !microphoneAllowed {
                        self.authorizationMessage = "Microphone permission is required."
                    } else {
                        self.authorizationMessage = nil
                    }
                }
            }
        }
    }

    func startListening() {
        guard !isListening else { return }

        transcript = ""
        authorizationMessage = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }

                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }

                    if error != nil || result?.isFinal == true {
                        self.stopListening()
                    }
                }
            }
        } catch {
            self.authorizationMessage = "Could not start voice input: \(error.localizedDescription)"
            self.stopListening()
        }
    }

    func stopListening() {
        guard isListening || audioEngine.isRunning else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
