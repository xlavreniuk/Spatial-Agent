//
//  CameraManager.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import AVFoundation
import Combine
import SwiftUI

final class CameraManager: ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    let session = AVCaptureSession()

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false

    init() {
        updateAuthorizationState()
    }

    func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationState = granted ? .authorized : .denied

                    if granted {
                        self?.configureAndStartSession()
                    }
                }
            }
        case .denied, .restricted:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    func stopSession() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func updateAuthorizationState() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            authorizationState = .notDetermined
        case .denied, .restricted:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !isConfigured {
                configureSession()
            }

            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            return
        }

        session.addInput(input)
        isConfigured = true
    }
}
