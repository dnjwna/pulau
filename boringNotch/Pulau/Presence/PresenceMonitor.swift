//
//  PresenceMonitor.swift
//  boringNotch — Pulau fork
//
//  EXPERIMENTAL, NOT A SECURITY FEATURE.
//  Detects whether *a* face is in front of the camera (Vision face rectangles,
//  on-device, no frames stored) and pauses music when you walk away, resuming
//  when you're back. It does not identify who the face belongs to.
//

import AVFoundation
import Combine
import Defaults
import Foundation
import Vision

final class PresenceMonitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = PresenceMonitor()

    enum Status: Equatable {
        case off
        case permissionDenied
        case noCamera
        case watching(present: Bool)

        var label: String {
            switch self {
            case .off: return "Off"
            case .permissionDenied: return "Camera access denied"
            case .noCamera: return "No camera found"
            case .watching(let present): return present ? "You're here" : "Away"
            }
        }
    }

    @Published private(set) var status: Status = .off

    // Session objects: touched only on `sessionQueue`.
    private let sessionQueue = DispatchQueue(label: "pulau.presence.session")
    private var session: AVCaptureSession?

    // Frame analysis: touched only on `videoQueue`.
    private let videoQueue = DispatchQueue(label: "pulau.presence.video")
    private var lastAnalysis: CFAbsoluteTime = 0
    private let analysisInterval: CFAbsoluteTime = 0.7
    private let faceRequest = VNDetectFaceRectanglesRequest()

    // State machine: main thread only.
    private var facePresent = true
    private var lastSeen = Date()
    private var pausedByPresence = false
    private var checkTimer: AnyCancellable?
    private var settingsObserver: AnyCancellable?

    private override init() {
        super.init()
        settingsObserver = Defaults.publisher(.presenceEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                change.newValue ? self?.start() : self?.stop()
            }
    }

    // MARK: Lifecycle (main thread)

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, Defaults[.presenceEnabled] else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.status = .permissionDenied
                    }
                }
            }
        default:
            status = .permissionDenied
        }
    }

    func stop() {
        checkTimer = nil
        pausedByPresence = false
        status = .off
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    private func startSession() {
        guard checkTimer == nil else { return }
        lastSeen = Date()
        facePresent = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { self.status = .noCamera }
                return
            }
            let session = AVCaptureSession()
            session.beginConfiguration()
            if session.canSetSessionPreset(.low) {
                session.sessionPreset = .low
            } else if session.canSetSessionPreset(.vga640x480) {
                session.sessionPreset = .vga640x480
            }
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.status = .noCamera }
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: self.videoQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
            self.session = session

            DispatchQueue.main.async {
                self.status = .watching(present: true)
                self.checkTimer = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in self?.evaluate() }
            }
        }
    }

    // MARK: Frames (videoQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysis >= analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceRequest])
            let found = !(faceRequest.results ?? []).isEmpty
            DispatchQueue.main.async { [weak self] in
                self?.facePresent = found
                if found { self?.lastSeen = Date() }
            }
        } catch {
            // Skip this frame.
        }
    }

    // MARK: Decisions (main thread)

    private func evaluate() {
        let music = MusicManager.shared
        let awayFor = Date().timeIntervalSince(lastSeen)
        let isAway = !facePresent && awayFor >= Double(max(5, Defaults[.presenceAwaySeconds]))

        status = .watching(present: !isAway)

        if isAway {
            if music.isPlaying {
                music.pause()
                pausedByPresence = true
            }
        } else if facePresent, pausedByPresence {
            pausedByPresence = false
            if Defaults[.presenceAutoResume], !music.isPlaying {
                music.play()
            }
        }
    }
}
