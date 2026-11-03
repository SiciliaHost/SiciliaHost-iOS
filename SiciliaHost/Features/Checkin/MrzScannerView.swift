import AVFoundation
import SwiftUI
import VisionKit

/// Scansione della zona MRZ di un documento (`MrzScannerScreen.kt`). Su Android: CameraX + ML Kit; qui il riconoscimento
/// del testo dal vivo di VisionKit (`DataScannerViewController`), che passa le righe lette a `MrzParser`. Al primo MRZ
/// valido si apre il modulo precompilato. Senza fotocamera, senza permesso o su un iPhone che non supporta lo scanner
/// resta "Inserisci manualmente".
struct MrzScannerView: View {
    let onDetected: (MrzData) -> Void
    let onManualEntry: () -> Void
    let onBack: () -> Void

    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var detected = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permission == .authorized && scannerAvailable {
                MrzDataScanner(onText: handle)
                    .ignoresSafeArea()
                MrzGuideOverlay(color: detected ? Color(hex: Brand.green) : .white)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Spacer()
                    Text("Posiziona il documento con il MRZ nel riquadro")
                        .appStyle(.bodyMedium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    manualButton
                }
                .padding(.bottom, 32)
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 16) {
                    Text(message)
                        .appStyle(.bodyMedium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if permission == .notDetermined {
                        Button("Concedi permesso") { requestPermission() }.buttonStyle(.appPrimary)
                    } else if permission == .denied || permission == .restricted {
                        Button("Apri Impostazioni") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.appPrimary)
                    }
                    manualButton
                }
                .padding(32)
            }
            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: Dimens.iconSmall, weight: .semibold))
                    }
                    .buttonStyle(AppIconButtonStyle(color: .white))
                    .accessibilityLabel("Indietro")
                    Text("Scansiona documento").appStyle(.titleSmall).foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.7))
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if permission == .notDetermined { requestPermission() } }
    }

    private var message: String {
        if permission == .authorized && !scannerAvailable {
            return "Questo iPhone non supporta la lettura del documento con la fotocamera. Inserisci i dati a mano."
        }
        return "Permesso fotocamera necessario per scansionare il documento."
    }

    private var manualButton: some View {
        Button(action: onManualEntry) {
            Label("Inserisci manualmente", systemImage: "pencil")
        }
        .buttonStyle(.appOutlined)
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in permission = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    private func handle(_ text: String) {
        guard !detected, let parsed = MrzParser.parse(text) else { return }
        detected = true
        onDetected(parsed)
    }
}

/// Riquadro guida del MRZ, in proporzione allo schermo (90 % della larghezza, nella parte bassa), come l'Android.
private struct MrzGuideOverlay: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.9, h = geo.size.height * 0.18
            roundedShape(8)
                .stroke(color, lineWidth: 3)
                .frame(width: w, height: h)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.65 + h / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lo scanner di testo di VisionKit. A ogni aggiornamento passa tutte le righe riconosciute, una per riga, in ordine
/// dall'alto: `MrzParser` cerca da sé le 2 o 3 righe del MRZ.
private struct MrzDataScanner: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onText = onText
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: (String) -> Void

        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            let lines: [(y: CGFloat, text: String)] = items.compactMap { item in
                guard case let .text(text) = item else { return nil }
                return (item.bounds.topLeft.y, text.transcript)
            }
            guard !lines.isEmpty else { return }
            onText(lines.sorted { $0.y < $1.y }.map(\.text).joined(separator: "\n"))
        }
    }
}
