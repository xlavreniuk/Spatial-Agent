//
//  CameraView.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import SwiftUI

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            cameraContent
                .ignoresSafeArea()

            VStack {
                Spacer()

                Button {
                    print("Camera button tapped")
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
        .task {
            cameraManager.requestCameraAccess()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch cameraManager.authorizationState {
        case .authorized:
            CameraPreviewView(session: cameraManager.session)
        case .notDetermined:
            Color.black
        case .denied:
            Color.black
                .overlay {
                    Text("Camera access is required")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
        }
    }
}

#Preview {
    CameraView()
}
