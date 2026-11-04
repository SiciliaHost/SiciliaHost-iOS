import FirebaseAuth
import Foundation
import Observation

/// Il nome visualizzato sta in Firebase Auth (`displayName`), lo stesso che il sito e l'elenco Host leggono (`ProfileViewModel.kt`).
@MainActor
@Observable
final class ProfileModel {
    private(set) var displayName = Auth.auth().currentUser?.displayName ?? ""
    private(set) var isSaving = false
    var error: String?

    /// Ritorna `true` se il nome è stato salvato (la vista chiude il foglio).
    func saveDisplayName(_ input: String) async -> Bool {
        guard !isSaving else { return false }
        if let problem = validateDisplayName(input) {
            error = problem
            return false
        }
        guard let user = Auth.auth().currentUser else {
            error = "Sessione scaduta: esci e accedi di nuovo per cambiare il nome"
            return false
        }
        let name = cleanDisplayName(input)
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let request = user.createProfileChangeRequest()
            request.displayName = name
            try await request.commitChanges()
            displayName = name
            return true
        } catch {
            self.error = "Non riesco a salvare il nome: controlla la connessione e riprova"
            return false
        }
    }
}

/// Ruolo e permessi su una casa, con "Lascia questa casa" per i collaboratori (`HouseAccessViewModel.kt`).
@MainActor
@Observable
final class HouseAccessModel {
    private(set) var scope: AccessScope?
    private(set) var property: Property?
    /// Nome (o email) del proprietario; nil finché non si conosce o se il server non lo dice.
    private(set) var ownerLabel: String?
    private(set) var isLoading = true
    private(set) var isBusy = false
    private(set) var error: String?
    /// L'utente è uscito dalla casa: la schermata si chiude.
    private(set) var left = false

    private let host = HostFunctionsService()

    func load(_ propertyId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let current = try await AccessSession.shared.scope()
            scope = current
            property = current.properties.first { $0.id == propertyId }
            guard let house = property else {
                error = "Casa non trovata"
                return
            }
            ownerLabel = current.isOwner(house) ? "Tu" : await fetchOwnerLabel(propertyId)
        } catch {
            self.error = describeHostError(error)
        }
    }

    /// Prima del deploy della Function aggiornata un collaboratore riceve un rifiuto: si omette il proprietario in silenzio.
    private func fetchOwnerLabel(_ propertyId: String) async -> String? {
        guard let members = try? await host.listMembers(propertyId: propertyId) else { return nil }
        return members.first { $0.role == .owner }.map(MembersLogic.label)
    }

    func leave() async {
        guard let scope, let property, !isBusy, canLeaveHouse(scope, property) else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await host.removeMember(propertyId: property.id, uid: scope.uid)
            // Scarta la sessione e avvisa la schermata principale, che ricarica le case.
            await AccessSession.shared.houseRemoved()
            left = true
        } catch {
            self.error = describeHostError(error)
        }
    }
}
