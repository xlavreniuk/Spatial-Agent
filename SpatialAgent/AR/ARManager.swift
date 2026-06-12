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

final class ARManager: ObservableObject {
    private weak var arView: ARView?
    private var arrowEntity: Entity?
    private var animationSubscription: (any Cancellable)?

    func configure(_ arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        arView.session.run(configuration)
    }

    func pauseSession() {
        arView?.session.pause()
        animationSubscription?.cancel()
        animationSubscription = nil
    }

    func placeTestArrow() {
        guard let placement = makePlacement(distance: 0.5) else { return }

        arrowEntity?.removeFromParent()

        let arrow = makeArrowEntity()
        arrow.look(at: placement.cameraPosition, from: placement.position, relativeTo: nil)
        placement.anchor.addChild(arrow)
        placement.arView.scene.addAnchor(placement.anchor)

        arrowEntity = arrow
        startRotatingArrow()
    }

    func placeInstructions(_ instructions: [RepairInstruction]) {
        guard let primaryInstruction = instructions.first(where: { $0.action.shouldRenderArrow }) else {
            return
        }

        placeActionArrow(for: primaryInstruction.action)
    }

    private func placeActionArrow(for action: RepairInstructionAction) {
        guard let placement = makePlacement(distance: 0.45) else { return }

        arrowEntity?.removeFromParent()

        let arrow = makeArrowEntity()
        arrow.look(at: placement.cameraPosition, from: placement.position, relativeTo: nil)
        placement.anchor.addChild(arrow)
        placement.arView.scene.addAnchor(placement.anchor)

        arrowEntity = arrow
        startAnimation(for: action)
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

    private func makePlacement(distance: Float) -> ArrowPlacement? {
        guard let arView else { return nil }

        let cameraTransform = arView.cameraTransform
        let cameraPosition = cameraTransform.translation
        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

        if let raycastResult = arView
            .raycast(from: screenCenter, allowing: .estimatedPlane, alignment: .any)
            .first
        {
            let position = raycastResult.worldTransform.translation
            return ArrowPlacement(
                arView: arView,
                anchor: AnchorEntity(world: position),
                position: position,
                cameraPosition: cameraPosition
            )
        }

        let forward = -cameraTransform.matrix.forwardVector
        let position = cameraPosition + (forward * distance)
        return ArrowPlacement(
            arView: arView,
            anchor: AnchorEntity(world: position),
            position: position,
            cameraPosition: cameraPosition
        )
    }

    private func makeArrowEntity() -> Entity {
        let arrow = Entity()

        let material = SimpleMaterial(color: .systemYellow, roughness: 0.35, isMetallic: false)

        let shaft = ModelEntity(
            mesh: .generateBox(size: [0.045, 0.045, 0.24]),
            materials: [material]
        )
        shaft.position.z = -0.08

        let head = ModelEntity(
            mesh: .generateBox(size: [0.14, 0.14, 0.08]),
            materials: [material]
        )
        head.position.z = -0.24
        head.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])

        arrow.addChild(shaft)
        arrow.addChild(head)

        return arrow
    }

    private func startRotatingArrow() {
        startAnimation(for: .rotateCCW)
    }

    private func startAnimation(for action: RepairInstructionAction) {
        guard let arView else { return }

        animationSubscription?.cancel()
        animationSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let arrowEntity = self?.arrowEntity else { return }

            let deltaTime = Float(event.deltaTime)

            switch action {
            case .tighten, .rotateCW:
                let rotation = simd_quatf(angle: deltaTime * 1.8, axis: [0, 1, 0])
                arrowEntity.orientation = rotation * arrowEntity.orientation
            case .unscrew, .rotateCCW:
                let rotation = simd_quatf(angle: -deltaTime * 1.8, axis: [0, 1, 0])
                arrowEntity.orientation = rotation * arrowEntity.orientation
            case .pull, .push:
                let direction: Float = action == .pull ? -1 : 1
                let offset = sin(Float(CACurrentMediaTime()) * 4) * 0.05 * direction
                arrowEntity.position.z = offset
            case .lift, .lower:
                let direction: Float = action == .lift ? 1 : -1
                let offset = abs(sin(Float(CACurrentMediaTime()) * 4)) * 0.08 * direction
                arrowEntity.position.y = offset
            case .warning:
                let scale = 1 + abs(sin(Float(CACurrentMediaTime()) * 5)) * 0.2
                arrowEntity.scale = [scale, scale, scale]
            default:
                let rotation = simd_quatf(angle: deltaTime * 1.2, axis: [0, 1, 0])
                arrowEntity.orientation = rotation * arrowEntity.orientation
            }
        }
    }
}

private struct ArrowPlacement {
    let arView: ARView
    let anchor: AnchorEntity
    let position: SIMD3<Float>
    let cameraPosition: SIMD3<Float>
}

private extension RepairInstructionAction {
    var shouldRenderArrow: Bool {
        self != .warning && self != .complete && self != .check
    }
}

private extension Transform {
    var translation: SIMD3<Float> {
        matrix.translation
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    var forwardVector: SIMD3<Float> {
        SIMD3(columns.2.x, columns.2.y, columns.2.z)
    }
}
