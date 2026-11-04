import MapKit
import SwiftUI

// Posizione della casa (`PositionSection.kt`, `PositionPickerDialog.kt`, `PositionMap.kt`, `MapMarkerIcons.kt`) con
// MapKit al posto di osmdroid. Il pin esatto (`coordinates`) è visibile sulla mappa del sito (mentre l'indirizzo civico
// resta riservato agli ospiti confermati); l'area di riserva (cerchio di 300 m) è usata se manca il pin. La geometria
// (50–250 m tra pin e centro dell'area) è in `PositionState`/`GeoMath`.

extension LatLng {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(_ c: CLLocationCoordinate2D) { self.init(lat: c.latitude, lng: c.longitude) }
}

/// Indirizzo + anteprima della mappa che apre l'editor.
struct PositionSection: View {
    @Binding var draft: SiteDraft
    let errors: [String: String]

    @State private var picking = false

    var body: some View {
        let state = draft.positionState
        SiteTextField(label: "Indirizzo", text: $draft.address, error: errors["address"], multiline: true)
        Button { picking = true } label: {
            VStack(spacing: 0) {
                if state.exact != nil {
                    PositionMapView(state: state, interactive: false, camera: .constant(Self.camera(for: state)))
                        .frame(height: 160)
                        .allowsHitTesting(false)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.primary)
                    Text(state.exact != nil ? "Modifica posizione" : "Imposta sulla mappa")
                        .appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Dimens.cardPadding)
            }
            .appCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.exact != nil ? "Posizione impostata. Tocca per modificarla" : "Nessuna posizione. Tocca per impostarla sulla mappa")
        if state.exact != nil {
            Button("Rimuovi posizione") { draft = draft.withPosition(PositionState()) }
                .buttonStyle(.appText(color: Theme.error))
        }
        ForEach([errors["lat"], errors["lng"], errors["area"]].compactMap { $0 }, id: \.self) { error in
            Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
        }
        Color.clear.frame(height: 0)
            .fullScreenCover(isPresented: $picking) {
                PositionPickerView(initialAddress: draft.address, initial: state, onDismiss: { picking = false }) { newState in
                    draft = draft.withPosition(newState)
                    picking = false
                }
            }
    }

    /// Inquadratura sul pin (con il cerchio dell'area visibile), o sulla Sicilia se non c'è.
    static func camera(for state: PositionState) -> MapCameraPosition {
        guard let center = state.area ?? state.exact else {
            return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.6, longitude: 14.0),
                                              span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.5)))
        }
        return .region(MKCoordinateRegion(center: center.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
    }
}

/// La mappa: pin esatto, centro dell'area (maniglia) e cerchio pubblico. Interattiva = un tocco sposta il pin, pin e
/// maniglia si trascinano.
struct PositionMapView: View {
    let state: PositionState
    let interactive: Bool
    var problem = false
    @Binding var camera: MapCameraPosition
    var onExactChange: (LatLng) -> Void = { _ in }
    var onAreaHandleChange: (LatLng) -> Void = { _ in }

    private static let space = "positionMap"

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: interactive ? .all : []) {
                if let area = state.area {
                    MapCircle(center: area.coordinate, radius: areaRadiusM)
                        .foregroundStyle((problem ? Theme.error : Theme.secondary).opacity(0.2))
                        .stroke(problem ? Theme.error : Theme.secondary, lineWidth: 2)
                    Annotation("Area pubblica", coordinate: area.coordinate, anchor: .center) {
                        marker(systemImage: "eye.circle.fill", color: Theme.secondary)
                            .highPriorityGesture(drag(proxy) { onAreaHandleChange($0) }, including: interactive ? .all : .none)
                    }
                }
                if let exact = state.exact {
                    Annotation("Pin esatto", coordinate: exact.coordinate, anchor: .bottom) {
                        marker(systemImage: "mappin.circle.fill", color: Theme.primary)
                            .highPriorityGesture(drag(proxy) { onExactChange($0) }, including: interactive ? .all : .none)
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
            .onTapGesture(coordinateSpace: .named(Self.space)) { point in
                guard interactive, let c = proxy.convert(point, from: .named(Self.space)) else { return }
                onExactChange(LatLng(c))
            }
        }
    }

    private func marker(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 30))
            .foregroundStyle(color, Color.white)
            .shadow(radius: 2)
    }

    private func drag(_ proxy: MapProxy, _ onEnd: @escaping (LatLng) -> Void) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.space)).onEnded { value in
            if let c = proxy.convert(value.location, from: .named(Self.space)) { onEnd(LatLng(c)) }
        }
    }
}

/// Editor a schermo intero: cerca un indirizzo, tocca la mappa o trascina il pin esatto e, se serve, la maniglia
/// dell'area pubblica. Nulla è salvato finché non si conferma qui E si tocca "Salva" nella scheda.
struct PositionPickerView: View {
    let initialAddress: String
    let onDismiss: () -> Void
    let onConfirm: (PositionState) -> Void

    @State private var state: PositionState
    @State private var query: String
    @State private var camera: MapCameraPosition
    @State private var results: [GeocodeResult] = []
    @State private var searching = false
    @State private var message: String?
    @State private var showCoordinates = false
    @State private var latText = ""
    @State private var lngText = ""

    init(initialAddress: String, initial: PositionState, onDismiss: @escaping () -> Void,
         onConfirm: @escaping (PositionState) -> Void) {
        self.initialAddress = initialAddress
        self.onDismiss = onDismiss
        self.onConfirm = onConfirm
        // Casa storica con pin ma senza area pubblica: l'area si crea subito (150 m, direzione casuale).
        let start: PositionState
        if let exact = initial.exact, initial.area == nil { start = initial.withExact(exact) } else { start = initial }
        _state = State(initialValue: start)
        _query = State(initialValue: initialAddress)
        _camera = State(initialValue: PositionSection.camera(for: start))
        _latText = State(initialValue: SiteNumbers.format(start.exact?.lat))
        _lngText = State(initialValue: SiteNumbers.format(start.exact?.lng))
    }

    var body: some View {
        let problem = state.problem()
        let canConfirm = state.exact != nil && problem == nil
        VStack(spacing: Dimens.itemSpacing) {
            CompactTopBar(title: "Posizione") {
                Button("Annulla", action: onDismiss).buttonStyle(.appText)
                Button("Conferma") { onConfirm(state) }.buttonStyle(.appPrimary).disabled(!canConfirm)
            }
            searchBlock.padding(.horizontal, Dimens.screenPadding)
            ZStack(alignment: .top) {
                PositionMapView(
                    state: state, interactive: true, problem: problem != nil, camera: $camera,
                    onExactChange: { moveExact(to: $0) },
                    onAreaHandleChange: { state = state.withAreaHandle($0) }
                )
                .accessibilityLabel("Mappa per scegliere la posizione. In alternativa usa Coordinate (avanzate).")
                if state.exact == nil {
                    Text("Tocca la mappa o cerca un indirizzo per posizionare il pin")
                        .appStyle(.bodyMedium)
                        .foregroundStyle(Theme.onSurface)
                        .padding(Dimens.cardPadding)
                        .appCard(container: Theme.surfaceContainerLowest.opacity(0.92))
                        .padding(Dimens.screenPadding)
                }
            }
            .frame(minHeight: 200)
            ScrollView {
                infoBlock(problem: problem).padding(.horizontal, Dimens.screenPadding)
            }
            .frame(maxHeight: 220)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func moveExact(to point: LatLng) {
        state = state.withExact(point)
        latText = SiteNumbers.format(state.exact?.lat)
        lngText = SiteNumbers.format(state.exact?.lng)
    }

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            HStack(spacing: 8) {
                AppTextField(label: "Indirizzo", text: $query)
                    .onSubmit { Task { await runSearch() } }
                    .submitLabel(.search)
                Button {
                    Task { await runSearch() }
                } label: {
                    if searching { ProgressView() } else { Text("Cerca") }
                }
                .buttonStyle(.appPrimary)
                .disabled(searching || query.trimmed.count < 3)
                .accessibilityLabel(searching ? "Ricerca in corso" : "Cerca")
            }
            if let message { Text(message).appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant) }
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: Dimens.itemSpacing) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                            Button {
                                moveExact(to: result.point)
                                camera = .region(MKCoordinateRegion(center: result.point.coordinate,
                                                                    latitudinalMeters: 600, longitudinalMeters: 600))
                                results = []
                            } label: {
                                Text(result.label).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.appOutlined)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    /// Nominatim: al massimo una richiesta per tocco di "Cerca" (niente ricerca mentre si scrive).
    private func runSearch() async {
        guard !searching, query.trimmed.count >= 3 else { return }
        searching = true
        message = nil
        switch await NominatimClient().search(query) {
        case let .success(found):
            results = found
            if found.isEmpty { message = "Nessun risultato. Prova con via e città." }
        case .failure:
            results = []
            message = "Ricerca non disponibile ora. Puoi comunque toccare la mappa."
        }
        searching = false
    }

    private func infoBlock(problem: String?) -> some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            // Legenda: forma + testo, non solo colore.
            Label("Pin esatto · visibile sulla mappa del sito", systemImage: "mappin.circle.fill")
                .appStyle(.labelMedium).foregroundStyle(Theme.primary)
            Label("Area di riserva · raggio 300 m", systemImage: "eye.circle.fill")
                .appStyle(.labelMedium).foregroundStyle(Theme.secondary)
            if let problem { Text(problem).appStyle(.bodyMedium).foregroundStyle(Theme.error) }
            if state.exact != nil {
                Text("Trascina il pin (o la maniglia dell'area) per spostarlo. Un tocco sulla mappa sposta il pin.")
                    .appStyle(.labelMedium).foregroundStyle(Theme.onSurfaceVariant)
            }
            if let exact = state.exact {
                Text(String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), exact.lat, exact.lng))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            Button(showCoordinates ? "Nascondi coordinate" : "Coordinate (avanzate)") { showCoordinates.toggle() }
                .buttonStyle(.appText)
            if showCoordinates {
                // Alternativa al trascinamento (VoiceOver, precisione, coordinate copiate da altrove): il pin si sposta
                // solo quando entrambi i numeri sono validi.
                FieldPair {
                    AppTextField(label: "Latitudine", text: $latText, keyboard: .numbersAndPunctuation)
                } b: {
                    AppTextField(label: "Longitudine", text: $lngText, keyboard: .numbersAndPunctuation)
                }
                .onChange(of: latText) { _, _ in pushTyped() }
                .onChange(of: lngText) { _, _ in pushTyped() }
            }
        }
        .padding(.bottom, Dimens.screenPadding)
    }

    private func pushTyped() {
        guard let a = SiteNumbers.parse(latText), let b = SiteNumbers.parse(lngText),
              (-90.0 ... 90.0).contains(a), (-180.0 ... 180.0).contains(b) else { return }
        let point = LatLng(lat: a, lng: b)
        guard point != state.exact else { return }
        state = state.withExact(point)
    }
}
