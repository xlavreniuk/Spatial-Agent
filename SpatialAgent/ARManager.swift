//
//  ARManager.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import ARKit
import Combine
import RealityKit

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
        guard let arView else { return }

        arrowEntity?.removeFromParent()

        let cameraTransform = arView.cameraTransform
        let forward = -cameraTransform.matrix.forwardVector
        let position = cameraTransform.translation + (forward * 0.5)

        let anchor = AnchorEntity(world: position)
        let arrow = makeArrowEntity()
        arrow.look(at: cameraTransform.translation, from: position, relativeTo: nil)
        anchor.addChild(arrow)
        arView.scene.addAnchor(anchor)

        arrowEntity = arrow
        startRotatingArrow()
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
        guard let arView else { return }

        animationSubscription?.cancel()
        animationSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let arrowEntity = self?.arrowEntity else { return }

            let rotation = simd_quatf(angle: Float(event.deltaTime) * 1.5, axis: [0, 1, 0])
            arrowEntity.orientation = rotation * arrowEntity.orientation
        }
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
