import FirebaseAuth
import Observation
import SwiftUI

/// Membri e inviti delle case di cui si è proprietari (`MembersViewModel.kt`).
@MainActor
@Observable
final class MembersModel {
    private(set) var ownedProperties: [Property] = []
    private(set) var selected: Property?
    private(set) var members: [MemberInfo] = []
    private(set) var isLoading = true
    private(set) var isBusy = false
    var error: String?
    var message: String?
    /// Uid del collaboratore i cui permessi sono in salvataggio (interruttori spenti).
    private(set) var savingPermissionsFor: String?
    private(set) var myUid = ""

    // Modulo "Invita un collaboratore" (nil = chiuso) e invito appena creato.
    var inviteForm: InviteForm?
    private(set) var invite: Invite?
    private(set) var inviteItems: [InviteShareItem] = []
    private(set) var inviteError: String?

    private let host = HostFunctionsService()

    func load(wanted: String? = nil) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let scope = try await AccessSession.shared.scope(forceRefresh: true)
            myUid = scope.uid
            ownedProperties = scope.owned
            let keep = wanted ?? selected?.id
            selected = scope.owned.first { $0.id == keep } ?? scope.owned.first
            try await refreshMembers()
        } catch {
            self.error = describeHostError(error)
        }
    }

    func select(_ id: String) async {
        selected = ownedProperties.first { $0.id == id }
        message = nil
        await guarded { try await self.refreshMembers() }
    }

    func openInviteComposer() {
        inviteForm = InviteForm.create(order: ownedProperties.map(\.id), currentId: selected?.id)
        invite = nil
        inviteError = nil
    }

    func closeInviteComposer() {
        inviteForm = nil
        invite = nil
        inviteError = nil
    }

    func createInvite() async {
        guard let form = inviteForm, form.canSubmit, !isBusy else { return }
        let grants = form.toGrants()
        let names = Dictionary(ownedProperties.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        isBusy = true
        inviteError = nil
        defer { isBusy = false }
        do {
            invite = try await host.createInvite(grants: grants)
            inviteItems = InviteText.shareItems(grants, namesById: names)
        } catch {
            inviteError = describeHostError(error)
        }
    }

    func remove(_ member: MemberInfo) async {
        guard let property = selected else { return }
        await guarded {
            try await self.host.removeMember(propertyId: property.id, uid: member.uid)
            try await self.refreshMembers()
            self.message = "\(MembersLogic.label(member)) non fa più parte della casa"
        }
    }

    /// Interruttore aggiornato subito; se la chiamata fallisce torna com'era.
    func setPermission(_ member: MemberInfo, _ permission: PropertyPermission, _ enabled: Bool) async {
        guard let property = selected, savingPermissionsFor == nil, MembersLogic.canEditPermissions(member) else { return }
        let previous = member.permissions
        let next = MembersLogic.toggle(previous, permission, enabled)
        guard next != previous else { return }
        savingPermissionsFor = member.uid
        error = nil
        replacePermissions(member.uid, next)
        defer { savingPermissionsFor = nil }
        do {
            try await host.setMemberPermissions(propertyId: property.id, uid: member.uid, permissions: next)
        } catch {
            replacePermissions(member.uid, previous)
            self.error = describeHostError(error)
        }
    }

    private func replacePermissions(_ uid: String, _ permissions: Set<PropertyPermission>) {
        members = members.map { m in
            guard m.uid == uid else { return m }
            var copy = m
            copy.permissions = permissions
            return copy
        }
    }

    /// Dopo un trasferimento completato si perde la proprietà: le case vanno ricaricate.
    func transfer(to email: String, keepPreviousOwner: Bool) async {
        guard let property = selected else { return }
        let target = email.trimmed
        await guarded {
            let result = try await self.host.transferOwnership(
                propertyId: property.id, newOwnerEmail: target, keepPreviousOwner: keepPreviousOwner
            )
            await AccessSession.shared.invalidate()
            self.message = result.completed
                ? "Proprietà trasferita a \(target)"
                : "\(target) non ha ancora un account: il passaggio avverrà al suo primo accesso con questa email"
            let scope = try await AccessSession.shared.scope(forceRefresh: true)
            self.ownedProperties = scope.owned
            self.selected = scope.owned.first { $0.id == property.id } ?? scope.owned.first
            self.invite = nil
            try await self.refreshMembers()
        }
    }

    private func refreshMembers() async throws {
        guard let property = selected else { members = []; return }
        members = MembersLogic.sort(try await host.listMembers(propertyId: property.id))
    }

    private func guarded(_ block: @escaping () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { try await block() } catch { self.error = describeHostError(error) }
    }
}

/// Membri e inviti (`MembersScreen.kt`): casa (con più case), membri con ruolo, permessi dei collaboratori (interruttori),
/// rimozione, "Invita un collaboratore", "Trasferisci proprietà…".
struct MembersView: View {
    let onBack: () -> Void
    var propertyId: String?
    @State private var model = MembersModel()
    @State private var memberToRemove: MemberInfo?
    @State private var showTransfer = false

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(title: "Membri e inviti", onBack: onBack)
            content
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load(wanted: propertyId) }
        .sheet(isPresented: Binding(get: { model.inviteForm != nil }, set: { if !$0 { model.closeInviteComposer() } })) {
            InviteComposerSheet(model: model)
        }
        .sheet(isPresented: $showTransfer) {
            if let selected = model.selected {
                TransferSheet(propertyName: selected.name, myEmail: Auth.auth().currentUser?.email ?? "") { email, keep in
                    Task { await model.transfer(to: email, keepPreviousOwner: keep) }
                }
            }
        }
        .confirmationDialog("Rimuovere il collaboratore?", isPresented: Binding(
            get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }
        ), titleVisibility: .visible, presenting: memberToRemove) { m in
            Button("Rimuovi", role: .destructive) { Task { await model.remove(m) } }
            Button("Annulla", role: .cancel) {}
        } message: { m in
            Text("\(MembersLogic.label(m)) non vedrà più questa casa.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.selected == nil {
            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selected = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    if model.ownedProperties.count > 1 {
                        SelectField(label: "Casa", options: model.ownedProperties.map(\.id), selected: selected.id,
                                    optionLabel: { id in model.ownedProperties.first { $0.id == id }?.name ?? id },
                                    onSelect: { id in Task { await model.select(id) } })
                    }
                    Text(selected.name).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                    if let m = model.message { Text(m).appStyle(.bodySmall).foregroundStyle(Theme.primary) }
                    if let e = model.error { Text(e).appStyle(.bodySmall).foregroundStyle(Theme.error) }

                    SectionLabel("Membri")
                    ForEach(model.members) { member in
                        MemberRow(
                            member: member,
                            isMe: member.uid == model.myUid,
                            removable: MembersLogic.canRemove(member, myUid: model.myUid),
                            saving: model.savingPermissionsFor == member.uid,
                            onRemove: { memberToRemove = member },
                            onPermission: { p, on in Task { await model.setPermission(member, p, on) } }
                        )
                    }

                    SectionLabel("Invita un collaboratore").padding(.top, Dimens.itemSpacing)
                    Button("Invita un collaboratore", action: model.openInviteComposer)
                        .buttonStyle(.appOutlined)
                        .disabled(model.isBusy)

                    SectionLabel("Proprietà").padding(.top, Dimens.itemSpacing)
                    Button("Trasferisci proprietà…") { showTransfer = true }
                        .buttonStyle(.appOutlined)
                        .disabled(model.isBusy)
                }
                .padding(Dimens.screenPadding)
            }
            .refreshable { await model.load() }
        } else {
            Text(model.error ?? "Non sei proprietario di nessuna casa.")
                .appStyle(.bodyMedium)
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(Dimens.screenPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MemberRow: View {
    let member: MemberInfo
    let isMe: Bool
    let removable: Bool
    let saving: Bool
    let onRemove: () -> Void
    let onPermission: (PropertyPermission, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(MembersLogic.label(member) + (isMe ? " (tu)" : "")).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                        .lineLimit(2)
                    Text(member.role == .owner ? "PROPRIETARIO" : "COLLABORATORE").appStyle(.labelSmall).foregroundStyle(Theme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if removable { Button("Rimuovi", action: onRemove).buttonStyle(.appText) }
            }
            if MembersLogic.canEditPermissions(member) {
                ForEach(PropertyPermission.allCases, id: \.self) { p in
                    Toggle(p.label, isOn: Binding(get: { member.permissions.contains(p) }, set: { onPermission(p, $0) }))
                        .appStyle(.bodyMedium)
                        .tint(Theme.primary)
                        .disabled(saving)
                }
                Text("Senza permessi il collaboratore gestisce prenotazioni, scorte e check-in.")
                    .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
            }
        }
        .padding(Dimens.cardPadding)
        .appCard()
    }
}

/// "Invita un collaboratore" su una o più case con i loro permessi; dopo la creazione codice, link e "Condividi".
private struct InviteComposerSheet: View {
    let model: MembersModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let invite = model.invite {
                    let expiry = dayMonthYearText(invite.expiresAt)
                    let link = InviteLink.build(invite.code)
                    Text("Invito creato").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                    Text(invite.code).appStyle(.headlineSmall).foregroundStyle(Theme.onSurface).textSelection(.enabled)
                    Text(link).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface).textSelection(.enabled)
                    Text("Monouso, valido fino al \(expiry).").appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                    ShareLink(item: InviteText.shareText(model.inviteItems, link: link, code: invite.code, expiryDate: expiry)) {
                        Text("Condividi")
                    }
                    .buttonStyle(.appPrimary)
                    HStack { Spacer(); Button("Chiudi", action: model.closeInviteComposer).buttonStyle(.appText) }
                } else if let form = model.inviteForm {
                    Text("Invita un collaboratore").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                    Text("Scegli le case e i permessi extra. Senza permessi il collaboratore gestisce prenotazioni, scorte e check-in.")
                        .appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant)
                    ForEach(model.ownedProperties) { property in
                        Toggle(property.name, isOn: Binding(
                            get: { form.isSelected(property.id) },
                            set: { model.inviteForm = form.withProperty(property.id, selected: $0) }
                        ))
                        .appStyle(.bodyLarge)
                        .tint(Theme.primary)
                        if form.isSelected(property.id) {
                            ForEach(PropertyPermission.allCases, id: \.self) { p in
                                Toggle(p.label, isOn: Binding(
                                    get: { form.permissionsOf(property.id).contains(p) },
                                    set: { model.inviteForm = form.withPermission(property.id, p, enabled: $0) }
                                ))
                                .appStyle(.bodyMedium)
                                .tint(Theme.primary)
                                .padding(.leading, 32)
                            }
                        }
                    }
                    if let problem = form.problem { Text(problem).appStyle(.bodySmall).foregroundStyle(Theme.error) }
                    if let error = model.inviteError { Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error) }
                    HStack {
                        Spacer()
                        Button("Annulla", action: model.closeInviteComposer).buttonStyle(.appText).disabled(model.isBusy)
                        Button("Crea invito") { Task { await model.createInvite() } }
                            .buttonStyle(.appPrimary)
                            .disabled(!form.canSubmit || model.isBusy)
                    }
                }
            }
            .padding(Dimens.screenPadding * 2)
        }
        .interactiveDismissDisabled(model.isBusy)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}

/// "Trasferisci …": email del nuovo proprietario e "Resto come collaboratore".
private struct TransferSheet: View {
    let propertyName: String
    let myEmail: String
    let onConfirm: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var keepPrevious = true

    var body: some View {
        let problem = MembersLogic.validateTransferEmail(email, myEmail: myEmail)
        VStack(alignment: .leading, spacing: 8) {
            Text("Trasferisci \"\(propertyName)\"").appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
            Text("Il nuovo proprietario avrà finanze, scheda e inviti. Tu perderai la gestione, salvo restare come collaboratore.")
                .appStyle(.bodySmall).foregroundStyle(Theme.onSurface)
            AppTextField(label: "Email del nuovo proprietario", text: $email,
                         error: !email.isEmpty ? problem : nil, keyboard: .emailAddress, capitalization: .never)
            Toggle("Resto come collaboratore", isOn: $keepPrevious).appStyle(.bodyMedium).tint(Theme.primary)
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.buttonStyle(.appText)
                Button("Trasferisci") {
                    onConfirm(email, keepPrevious)
                    dismiss()
                }
                .buttonStyle(.appPrimary)
                .disabled(problem != nil)
            }
        }
        .padding(Dimens.screenPadding * 2)
        .presentationDetents([.medium])
        .presentationBackground(Theme.surfaceContainerLow)
    }
}
