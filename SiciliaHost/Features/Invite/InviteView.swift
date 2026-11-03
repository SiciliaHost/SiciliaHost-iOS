import FirebaseAuth
import Observation
import SwiftUI

/// Stato della schermata invito (`InviteViewModel.kt`).
enum InviteUIState: Equatable {
    case loading
    case preview(InvitePreview)
    case error(String)
    case busy
}

/// Accettare o rifiutare un invito (`InviteViewModel.kt`). Testabile con un `InviteAPI` finto.
@MainActor
@Observable
final class InviteModel {
    private(set) var state: InviteUIState = .loading
    let code: String
    private let api: InviteAPI
    private let pending: PendingInvite
    @ObservationIgnored private var started = false

    init(code: String, api: InviteAPI, pending: PendingInvite) {
        self.code = code
        self.api = api
        self.pending = pending
    }

    /// Carica l'anteprima una volta sola; dopo `close` riparte da capo.
    func start() async {
        guard !started else { return }
        started = true
        state = .loading
        do {
            state = .preview(try await api.getInvite(code: code))
        } catch {
            state = .error(describeHostError(error))
        }
    }

    func accept() async {
        await act {
            _ = try await self.api.redeemInvite(code: self.code)
            self.pending.notifyAccepted()
        }
    }

    func decline() async { await act { try await self.api.declineInvite(code: self.code) } }

    /// Chiude la schermata (anche dopo un errore): il codice non è più in attesa.
    func close() {
        started = false
        pending.clear()
    }

    private func act(_ block: @escaping () async throws -> Void) async {
        guard case .preview = state else { return }
        state = .busy
        do {
            try await block()
            close()
        } catch {
            state = .error(describeHostError(error))
        }
    }
}

/// Sopra a tutto (non è una destinazione): compare solo con un codice in attesa e un utente collegato. Senza accesso
/// resta il login, e la schermata arriva da sola dopo l'accesso (il codice resta in memoria).
struct InviteOverlay: View {
    let uid: String?
    private var pending: PendingInvite { .shared }

    var body: some View {
        if let code = pending.code, uid != nil {
            InviteScreen(model: InviteModel(code: code, api: HostFunctionsService(), pending: pending))
                .id("\(uid ?? "")_\(code)")
                .transition(.opacity)
        }
    }
}

struct InviteScreen: View {
    @State var model: InviteModel

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: Dimens.itemSpacing) {
                    switch model.state {
                    case .loading, .busy:
                        ProgressView().tint(Theme.primary).padding(32)
                    case let .error(message):
                        Text("Invito non disponibile").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                        Text(message).appStyle(.bodyMedium).foregroundStyle(Theme.error).multilineTextAlignment(.center)
                        Button("Chiudi", action: model.close).buttonStyle(.appOutlined).frame(maxWidth: .infinity)
                    case let .preview(preview):
                        previewContent(preview)
                    }
                }
                .frame(maxWidth: 400)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity, minHeight: 500)
            }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private func previewContent(_ preview: InvitePreview) -> some View {
        Text(InviteText.headline(preview.inviterEmail)).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            .multilineTextAlignment(.center)
        ForEach(preview.grants, id: \.propertyId) { g in
            VStack(alignment: .leading, spacing: 2) {
                Text(g.propertyName.trimmed.isEmpty ? "Casa" : g.propertyName).appStyle(.titleSmall).foregroundStyle(Theme.onSurface)
                Text(InviteText.permissionsText(g.permissions)).appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(InviteText.baseManagementNote).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).multilineTextAlignment(.center)
        Text("Valido fino al \(dayMonthYearText(preview.expiresAt))").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
        Button("Accetta") { Task { await model.accept() } }.buttonStyle(.appPrimary).frame(maxWidth: .infinity)
        Button("Rifiuta") { Task { await model.decline() } }.buttonStyle(.appOutlined).frame(maxWidth: .infinity)
    }
}
