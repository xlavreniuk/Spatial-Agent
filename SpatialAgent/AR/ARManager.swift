//
//  ARManager.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import ARKit
import Combine
import RealityKit
import UIKit
import Vision

struct ObjectOverlay: Identifiable, Equatable {
    let id: String
    let label: String
    let boundingBox: CGRect
    let isTarget: Bool
}

final class ARManager: NSObject, ObservableObject {
    @Published private(set) var objectOverlays: [ObjectOverlay] = []

    private weak var arView: ARView?
    private let trackingQueue = DispatchQueue(label: "spatialagent.object-tracking")
    private let sequenceHandler = VNSequenceRequestHandler()
    private var trackingRequests: [VNTrackObjectRequest] = []
    private var isTrackingFrame = false

    func configure(_ arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        arView.session.run(configuration)
    }

    func pauseSession() {
        arView?.session.pause()
        clearObjectOverlays()
    }

    func placeTestArrow() {
        showFallbackOverlay(label: "target")
    }

    func placeInstructions(_ instructions: [RepairInstruction], detectedObjects: [DetectedObject] = []) {
        let targetIDs = Set(instructions.map(\.target))
        let overlays = detectedObjects.compactMap { object -> ObjectOverlay? in
            guard let boundingBox = object.boundingBox?.clampedCGRect else { return nil }

            return ObjectOverlay(
                id: object.id,
                label: object.label,
                boundingBox: boundingBox,
                isTarget: targetIDs.contains(object.id)
            )
        }

        if overlays.isEmpty {
            showFallbackOverlay(label: fallbackLabel(for: instructions))
            return
        }

        setObjectOverlays(overlays)
        startTracking(overlays)
    }

    func currentCameraImage() -> UIImage? {
        guard let pixelBuffer = arView?.session.currentFrame?.capturedImage else {
            print("Gemini test error: No AR camera frame is available yet.")
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(.right)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Gemini test error: Could not convert AR camera frame to UIImage.")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func setObjectOverlays(_ overlays: [ObjectOverlay]) {
        DispatchQueue.main.async {
            self.objectOverlays = overlays
        }
    }

    func clearObjectOverlays() {
        setObjectOverlays([])
        trackingQueue.async {
            self.trackingRequests = []
            self.isTrackingFrame = false
        }
    }

    private func showFallbackOverlay(label: String) {
        let overlay = ObjectOverlay(
            id: "fallback-target",
            label: label,
            boundingBox: CGRect(x: 0.28, y: 0.32, width: 0.44, height: 0.28),
            isTarget: true
        )
        setObjectOverlays([overlay])
        trackingQueue.async {
            self.trackingRequests = []
        }
    }

    private func fallbackLabel(for instructions: [RepairInstruction]) -> String {
        instructions
            .first(where: { $0.target != "scene" })?
            .target
            .replacingOccurrences(of: "_", with: " ") ?? "target"
    }

    private func startTracking(_ overlays: [ObjectOverlay]) {
        let requests = overlays.map { overlay in
            let observation = VNDetectedObjectObservation(
                boundingBox: overlay.boundingBox.visionBoundingBox
            )
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            return request
        }

        trackingQueue.async {
            self.trackingRequests = requests
        }
    }
}

extension ARManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        trackingQueue.async {
            guard !self.trackingRequests.isEmpty, !self.isTrackingFrame else { return }

            self.isTrackingFrame = true
            defer { self.isTrackingFrame = false }

            do {
                try self.sequenceHandler.perform(
                    self.trackingRequests,
                    on: frame.capturedImage,
                    orientation: .right
                )

                let trackedBoxes = self.trackingRequests.compactMap { request -> CGRect? in
                    guard
                        let observation = request.results?.first as? VNDetectedObjectObservation,
                        observation.confidence >= 0.35
                    else {
                        return nil
                    }

                    return observation.boundingBox.displayBoundingBox
                }

                guard !trackedBoxes.isEmpty else { return }

                DispatchQueue.main.async {
                    guard trackedBoxes.count == self.objectOverlays.count else { return }

                    self.objectOverlays = zip(self.objectOverlays, trackedBoxes).map { overlay, box in
                        ObjectOverlay(
                            id: overlay.id,
                            label: overlay.label,
                            boundingBox: box,
                            isTarget: overlay.isTarget
                        )
                    }
                }
            } catch {
                print("Vision tracking error: \(error.localizedDescription)")
            }
        }
    }
}

private extension NormalizedBoundingBox {
    var clampedCGRect: CGRect {
        let minX = x.clamped(to: 0...1)
        let minY = y.clamped(to: 0...1)
        let maxX = (x + width).clamped(to: 0...1)
        let maxY = (y + height).clamped(to: 0...1)

        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(max(0.04, maxX - minX)),
            height: CGFloat(max(0.04, maxY - minY))
        )
    }
}

private extension CGRect {
    var visionBoundingBox: CGRect {
        CGRect(
            x: origin.x,
            y: 1 - origin.y - height,
            width: width,
            height: height
        )
    }

    var displayBoundingBox: CGRect {
        CGRect(
            x: origin.x,
            y: 1 - origin.y - height,
            width: width,
            height: height
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
