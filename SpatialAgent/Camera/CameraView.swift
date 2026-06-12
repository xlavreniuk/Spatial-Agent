//
//  CameraView.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import SwiftUI

struct CameraView: View {
    @StateObject private var arManager = ARManager()

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()

            VStack {
                Spacer()

                Button {
                    print("Camera button tapped")
                    arManager.placeTestArrow()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 74, height: 74)
                        .overlay {
                            Circle()
                                .stroke(.black.opacity(0.2), lineWidth: 2)
                                .frame(width: 62, height: 62)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                }
                .accessibilityLabel("Camera button")
                .padding(.bottom, 36)
            }
        }
        .background(.black)
        .onDisappear {
            arManager.pauseSession()
        }
    }
}

#Preview {
    CameraView()
}
