//
//  CameraView.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import SwiftUI

struct CameraView: View {
    @StateObject private var arManager = ARManager()
    @StateObject private var voiceManager = VoiceManager()
    @State private var statusText = "Tap the button and ask a repair question."
    @State private var geminiResponse: String?
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()

            VStack {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(.top, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(voiceManager.isListening ? "Listening" : "Your question")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(displayedQuestion)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let geminiResponse {
                        Divider()
                            .background(.white.opacity(0.25))

                        Text(geminiResponse)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)

                Button {
                    handleAskButtonTapped()
                } label: {
                    ZStack {
                        Circle()
                            .fill(voiceManager.isListening ? .red : .white)
                            .frame(width: 74, height: 74)
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

                        Image(systemName: buttonIconName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(voiceManager.isListening ? .white : .black)
                    }
                }
                .disabled(isProcessing)
                .accessibilityLabel(voiceManager.isListening ? "Submit question" : "Start voice question")
                .padding(.bottom, 36)
            }
        }
        .background(.black)
        .onAppear {
            voiceManager.requestAuthorization()
        }
        .onChange(of: voiceManager.authorizationMessage) { _, message in
            if let message {
                statusText = message
            }
        }
        .onDisappear {
            voiceManager.stopListening()
            arManager.pauseSession()
        }
    }

    private var displayedQuestion: String {
        if voiceManager.transcript.isEmpty {
            "Example: How do I open this bottle of water?"
        } else {
            voiceManager.transcript
        }
    }

    private var buttonIconName: String {
        if isProcessing {
            "hourglass"
        } else if voiceManager.isListening {
            "paperplane.fill"
        } else {
            "mic.fill"
        }
    }

    private func handleAskButtonTapped() {
        if voiceManager.isListening {
            voiceManager.stopListening()
            submitQuestion()
        } else {
            geminiResponse = nil
            statusText = "Listening..."
            voiceManager.startListening()
        }
    }

    private func submitQuestion() {
        let question = voiceManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !question.isEmpty else {
            statusText = "I did not hear a question. Tap and ask again."
            return
        }

        guard let image = arManager.currentCameraImage() else {
            statusText = "No AR camera frame yet. Point at the object and try again."
            return
        }

        Task {
            do {
                isProcessing = true
                statusText = "Gemini is looking..."
                print("Gemini repair request: \(question)")

                let step = try await GeminiService.shared.generateRepairStep(
                    image: image,
                    userRequest: question
                )

                geminiResponse = step.voice
                statusText = "Step \(step.step)"
                arManager.placeInstructions(step.instructions)
                print("Gemini repair response: \(step)")
            } catch {
                geminiResponse = error.localizedDescription
                statusText = "Gemini error"
                print("Gemini repair error: \(error.localizedDescription)")
            }

            isProcessing = false
        }
    }
}

#Preview {
    CameraView()
}
