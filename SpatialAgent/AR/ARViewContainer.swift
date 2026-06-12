//
//  ARViewContainer.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let arManager: ARManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arManager.configure(arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
