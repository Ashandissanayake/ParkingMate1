import SwiftUI
import AVFoundation
import VisionKit
import PhotosUI

// MARK: - Camera (design: parking_spot_photo)

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

// MARK: - VisionKit live scanner (design: visionkit_camera_scanner / detect_parking_number_visionkit)

struct ParkingNumberScannerView: UIViewControllerRepresentable {
    var onCandidate: (String?) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()],
                                                qualityLevel: .accurate,
                                                recognizesMultipleItems: true,
                                                isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCandidate: onCandidate) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCandidate: (String?) -> Void
        init(onCandidate: @escaping (String?) -> Void) { self.onCandidate = onCandidate }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) { report(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) { report(allItems) }

        private func report(_ items: [RecognizedItem]) {
            let strings: [String] = items.compactMap {
                if case .text(let text) = $0 { return text.transcript }
                return nil
            }
            onCandidate(ParkingNumberParser.bestCandidate(from: strings))
        }
    }
}

struct ParkingNumberScannerSheet: View {
    var onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraGranted: Bool?
    @State private var candidate: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var ocrBusy = false
    @State private var ocrMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            if cameraGranted == true, ParkingNumberScannerView.isSupported {
                ParkingNumberScannerView { candidate = $0 }.ignoresSafeArea()
            } else if cameraGranted != nil {
                fallback
            }
            VStack(spacing: 12) {
                statusPill
                if let candidate {
                    VStack(spacing: 6) {
                        Text(candidate).font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Parking Number").foregroundStyle(Theme.textSecondary)
                        Button("Use \(candidate)") { onUse(candidate); dismiss() }
                            .buttonStyle(.primary).padding(.top, 6)
                    }
                    .padding(20)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous))
                }
            }
            .padding()
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white).padding(14)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Close scanner").padding()
        }
        .task { cameraGranted = await AVCaptureDevice.requestAccess(for: .video) }
        .onChange(of: photoItem) { _, item in Task { await runOCR(on: item) } }
    }

    private var statusPill: some View {
        Label(candidate == nil ? "Detecting parking number…" : "\(candidate ?? "") detected",
              systemImage: candidate == nil ? "viewfinder" : "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Simulator / no camera / permission denied: read the number from a photo with the Vision framework.
    private var fallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown").font(.system(size: 48)).foregroundStyle(.white)
            Text(cameraGranted == false ? "Camera access is off. Pick a photo of the bay sign instead."
                                         : "Live scanning isn't available on this device. Pick a photo instead.")
                .multilineTextAlignment(.center).foregroundStyle(.white)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(ocrBusy ? "Reading…" : "Choose photo", systemImage: "photo")
            }
            .buttonStyle(.secondary).frame(maxWidth: 260)
            if let ocrMessage { Text(ocrMessage).font(.footnote).foregroundStyle(.white.opacity(0.8)) }
        }
        .padding(32)
    }

    private func runOCR(on item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        ocrBusy = true; defer { ocrBusy = false }
        if let number = await TextRecognitionService.parkingNumber(in: image) {
            candidate = number; ocrMessage = nil
        } else {
            ocrMessage = "No bay number found in that photo."
        }
    }
}

// MARK: - Voice note sheet (design: add_voice_note)

struct VoiceNoteSheet: View {
    var onSave: (String, String) -> Void          // (fileName, transcript)
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var fileName: String?
    @State private var transcript = ""
    @State private var errorMessage: String?

    private var voice: VoiceNoteService { container.voice }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Button(action: toggleRecording) {
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44)).foregroundStyle(.white)
                        .frame(width: 112, height: 112)
                        .background(voice.isRecording ? Theme.danger : Theme.primary, in: Circle())
                        .overlay(Circle().stroke(Theme.primary.opacity(0.2), lineWidth: 12 + 20 * voice.level))
                }
                .accessibilityLabel(voice.isRecording ? "Stop recording" : "Start recording")

                Text(voice.isRecording ? "Recording… \(Formatters.clock(voice.elapsed))"
                                       : (fileName == nil ? "Tap to record your note" : "Note recorded"))
                    .foregroundStyle(Theme.textSecondary)

                if voice.isTranscribing { ProgressView("Transcribing on device…") }
                if !transcript.isEmpty {
                    Text("“\(transcript)”").padding().frame(maxWidth: .infinity)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                if let errorMessage { ErrorBanner(message: errorMessage) }
                Spacer()

                if let fileName, !voice.isRecording {
                    HStack(spacing: 12) {
                        Button { voice.isPlaying ? voice.stopPlayback() : voice.play(fileName: fileName) } label: {
                            Label(voice.isPlaying ? "Stop" : "Play", systemImage: voice.isPlaying ? "stop.circle" : "play.circle")
                        }.buttonStyle(.secondary)
                        Button("Save Note") { onSave(fileName, transcript); dismiss() }.buttonStyle(.primary)
                    }
                }
            }
            .padding(24)
            .navigationTitle("Add Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } } }
            .background(Theme.background.ignoresSafeArea())
        }
    }

    private func toggleRecording() {
        Task {
            if voice.isRecording {
                voice.stopRecording()
                guard let name = fileName else { return }
                do { transcript = try await voice.transcribe(fileName: name); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            } else {
                do { fileName = try await voice.startRecording(); transcript = ""; errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func cancel() {
        if voice.isRecording { voice.stopRecording() }
        voice.stopPlayback()
        if let fileName { voice.deleteFile(named: fileName) }
        dismiss()
    }
}
