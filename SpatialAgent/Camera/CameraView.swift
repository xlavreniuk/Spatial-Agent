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

            GeometryReader { proxy in
                ForEach(arManager.objectOverlays) { overlay in
                    ObjectOverlayBox(overlay: overlay, containerSize: proxy.size)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

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
            arManager.clearObjectOverlays()
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
                arManager.placeInstructions(
                    step.instructions,
                    detectedObjects: step.objects ?? []
                )
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

private struct ObjectOverlayBox: View {
    let overlay: ObjectOverlay
    let containerSize: CGSize

    private let lineWidth: CGFloat = 3

    var body: some View {
        let rect = displayRect

        ZStack(alignment: .topLeading) {
            CornerBorder()
                .stroke(borderColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
                .frame(width: rect.width, height: rect.height)

            Text(overlay.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: max(72, rect.width), alignment: .leading)
                .background(borderColor, in: RoundedRectangle(cornerRadius: 4))
                .offset(y: -28)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private var displayRect: CGRect {
        let rawRect = CGRect(
            x: overlay.boundingBox.minX * containerSize.width,
            y: overlay.boundingBox.minY * containerSize.height,
            width: overlay.boundingBox.width * containerSize.width,
            height: overlay.boundingBox.height * containerSize.height
        )

        let minSize: CGFloat = 72
        let width = min(max(minSize, rawRect.width), max(minSize, containerSize.width - 16))
        let height = min(max(minSize, rawRect.height), max(minSize, containerSize.height - 50))
        let maxX = max(8, containerSize.width - width - 8)
        let maxY = max(42, containerSize.height - height - 8)
        let x = min(max(rawRect.midX - width / 2, 8), maxX)
        let y = min(max(rawRect.midY - height / 2, 42), maxY)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var borderColor: Color {
        overlay.isTarget ? .yellow : .cyan
    }
}

private struct CornerBorder: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(28, rect.width * 0.32, rect.height * 0.32)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

#Preview {
    CameraView()
}
