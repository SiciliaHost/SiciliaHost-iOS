import SwiftUI

/// Il tab "Case" (`CasesScreen.kt`): elenco con filtro (super-admin), annunci da approvare in evidenza, scheda a sezioni.
/// La scheda e l'elenco degli host prendono il posto dell'elenco (come sul telefono Android).
struct CasesView: View {
    let model: CasesModel
    var tourTarget: TourTarget?
    let onOpenMembers: () -> Void
    /// Apre la creazione guidata; nil = il foglio con il solo nome.
    var onNewCase: (() -> Void)?
    /// Apre il secondo livello della creazione guidata (dati del sito) per la casa indicata.
    var onOpenSiteWizard: (String) -> Void = { _ in }

    @State private var openId: String?
    @State private var openedByTour = false
    @State private var showHosts = false
    @State private var showNew = false
    @State private var newName = ""
    @State private var toast: String?

    var body: some View {
        Group {
            if showHosts && model.isSuperAdmin {
                HostsView(model: model, onBack: { showHosts = false }, onOpenCase: { id in
                    showHosts = false
                    openId = id
                })
            } else if let id = openId, let item = model.item(id) {
                CaseDetailView(initial: item, model: model, tourTarget: tourTarget, onBack: { openId = nil },
                               onOpenMembers: onOpenMembers, onOpenSiteWizard: onOpenSiteWizard)
                    .id(id)
            } else {
                listScreen
            }
        }
        // Il modello vive quanto la schermata principale: si ricarica a ogni ingresso nel tab.
        .task { if !model.isLoading { await model.load() } }
        .sheet(isPresented: $showNew) { newCaseSheet }
        // Tour guidato, passo "Importa Excel Booking": apre la prima casa gestita (la sezione Gestione la apre la scheda)
        // e la richiude quando il tour va avanti.
        .onChange(of: TourOpenKey(target: tourTarget, count: model.items.count), initial: true) { _, key in
            if key.target == .caseBookingImport {
                if openId == nil, let first = model.items.first(where: \.canManage) {
                    openId = first.property.id
                    openedByTour = true
                }
            } else if openedByTour {
                openId = nil
                openedByTour = false
            }
        }
    }

    private var listScreen: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if model.isLoading && model.items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.loadError, model.items.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).appStyle(.bodyMedium).foregroundStyle(Theme.error).multilineTextAlignment(.center)
                        Button("Riprova") { Task { await model.load() } }.buttonStyle(.appPrimary)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    caseList
                }
            }
            Button {
                if let onNewCase {
                    onNewCase()
                } else {
                    newName = ""
                    model.clearMessages()
                    showNew = true
                }
            } label: {
                Image(systemName: "plus").font(.system(size: Dimens.iconSmall, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.appPrimary(container: Theme.primary, content: Theme.onPrimary))
            .accessibilityLabel("Nuova casa")
            .padding(Dimens.screenPadding)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .appStyle(.bodyMedium)
                    .foregroundStyle(Theme.onSurface)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .appCard(container: Theme.surfaceContainerHigh)
                    .padding(Dimens.screenPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Messaggi ed errori delle azioni: avviso breve sopra l'elenco (lo snackbar dell'Android).
        .onChange(of: model.actionError ?? model.message) { _, note in
            guard let note, openId == nil else { return }
            withAnimation { toast = note }
            model.clearMessages()
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { if toast == note { toast = nil } }
            }
        }
    }

    private var caseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                // Un ricaricamento fallito con la lista già piena non deve passare inosservato.
                if let error = model.loadError, !model.items.isEmpty {
                    HStack {
                        Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
                        Spacer()
                        Button("Riprova") { Task { await model.load() } }.buttonStyle(.appText)
                    }
                }
                if model.isSuperAdmin { adminControls }
                let summaries = model.summaries
                if summaries.isEmpty {
                    Text(emptyText)
                        .appStyle(.bodyMedium)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(32)
                } else {
                    ForEach(summaries) { s in
                        let other = model.isSuperAdmin && !(model.scope.map { s.memberUids.contains($0.uid) } ?? true)
                        CaseCard(summary: s, hostLabel: other ? hostLabel(s.ownerUid) : nil) { openId = s.id }
                    }
                }
            }
            .padding(Dimens.screenPadding)
        }
        .refreshable { await model.load() }
    }

    private var emptyText: String {
        switch model.filter {
        case .mine: return "Nessuna casa tua."
        case .all: return "Nessuna casa."
        case .host: return "Questo host non ha case."
        }
    }

    /// Una tendina sola: le mie case, tutte, quelle di un host, oppure l'elenco degli host.
    @ViewBuilder
    private var adminControls: some View {
        let hostsOption = "hosts"
        let options = ["mine", "all"] + model.hosts.map { "host:\($0.uid)" } + [hostsOption]
        let selected: String = {
            switch model.filter {
            case .mine: return "mine"
            case .all: return "all"
            case let .host(uid): return "host:\(uid)"
            }
        }()
        SelectField(
            label: "Mostra",
            options: options,
            selected: selected,
            optionLabel: { option in
                switch option {
                case "mine": return "Le mie case"
                case "all": return "Tutte le case"
                case hostsOption: return "Elenco host…"
                default:
                    let uid = String(option.dropFirst("host:".count))
                    guard let h = model.hosts.first(where: { $0.uid == uid }) else { return hostLabel(uid) ?? "Host" }
                    return "\(hostName(h)) · \(h.propertyCount) case"
                }
            },
            onSelect: { option in
                switch option {
                case "mine": model.filter = .mine
                case "all": model.filter = .all
                case hostsOption: showHosts = true
                default: model.filter = .host(uid: String(option.dropFirst("host:".count)))
                }
            }
        )
        let pending = model.pendingAll
        if pending > 0 {
            HStack {
                Text("\(pending) \(pending == 1 ? "annuncio" : "annunci") da approvare")
                    .appStyle(.titleSmall)
                    .foregroundStyle(Theme.onSecondaryContainer)
                Spacer()
                Button("Mostra") { model.filter = .all }.buttonStyle(.appText(color: Theme.onSecondaryContainer))
            }
            .padding(.leading, Dimens.cardPadding)
            .appCard(container: Theme.secondaryContainer)
        }
    }

    private func hostLabel(_ uid: String?) -> String? {
        guard let h = model.hosts.first(where: { $0.uid == uid }) else { return nil }
        let label = h.displayName.trimmed.isEmpty ? h.email : h.displayName
        return label.trimmed.isEmpty ? nil : label
    }

    private var newCaseSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nuova casa").appStyle(.headlineSmall).foregroundStyle(Theme.onSurface)
            AppTextField(label: "Nome della struttura", text: $newName, capitalization: .words)
            Text("La casa nasce come bozza: completa i dati nella sua scheda e invia per approvazione quando è pronta.")
                .appStyle(.bodySmall)
                .foregroundStyle(Theme.onSurfaceVariant)
            if let error = model.actionError {
                Text(error).appStyle(.bodySmall).foregroundStyle(Theme.error)
            }
            HStack {
                Spacer()
                Button("Annulla") { showNew = false }.buttonStyle(.appText).disabled(model.busy)
                Button(model.busy ? "Creazione…" : "Crea") {
                    Task {
                        if let id = await model.createCase(name: newName) {
                            showNew = false
                            openId = id
                        }
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(newName.trimmed.isEmpty || model.busy)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(model.busy)
    }
}

private struct TourOpenKey: Equatable {
    let target: TourTarget?
    let count: Int
}

func hostName(_ h: HostRow) -> String {
    let label = h.displayName.trimmed.isEmpty ? h.email : h.displayName
    return label.trimmed.isEmpty ? "Account non più presente" : label
}

/// Colori dello stato nella lingua del progetto: giallo = da rivedere, verde = confermato, rosso = problema.
func listingStatusColors(_ status: ListingStatus) -> (background: Color, foreground: Color) {
    switch status {
    case .pending: return (Theme.secondaryContainer, Theme.onSecondaryContainer)
    case .approved: return (Theme.primaryContainer, Theme.onPrimaryContainer)
    case .rejected: return (Theme.errorContainer, Theme.onErrorContainer)
    case .draft: return (Theme.surfaceContainerHigh, Theme.onSurfaceVariant)
    }
}

struct ListingStatusPill: View {
    let status: ListingStatus

    var body: some View {
        let colors = listingStatusColors(status)
        Text(status.label.uppercased())
            .appStyle(.labelSmall)
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(roundedShape(Radius.small).fill(colors.background))
    }
}

/// Una riga dell'elenco: nome, stato, zona/prezzo/foto, host (solo per il super-admin sulle case altrui), cosa manca.
struct CaseCard: View {
    let summary: CaseSummary
    let hostLabel: String?
    let onTap: () -> Void

    var body: some View {
        let pending = summary.status == .pending
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(summary.name.trimmed.isEmpty ? "Senza nome" : summary.name)
                        .appStyle(.titleSmall)
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ListingStatusPill(status: summary.status)
                }
                Text(detailLine)
                    .appStyle(.bodySmall)
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(2)
                if let hostLabel {
                    Text(hostLabel).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
                }
                if summary.status == .draft && !summary.missing.isEmpty {
                    Text("Mancano: \(summary.missing.joined(separator: ", "))")
                        .appStyle(.labelMedium)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(3)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(Dimens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(container: pending ? Theme.secondaryContainer.opacity(0.25) : Theme.surfaceContainerLow)
            .overlay {
                if pending { roundedShape(Radius.medium).strokeBorder(Theme.secondary, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailLine: String {
        var parts: [String] = []
        if let zone = summary.zone, !zone.trimmed.isEmpty { parts.append(zone) }
        if let price = summary.price { parts.append("€ \(SiteNumbers.format(price))/notte") }
        parts.append(summary.coverUrl != nil ? "con foto" : "senza foto")
        return parts.joined(separator: " · ")
    }
}

/// Elenco degli host (solo super-admin, `HostsScreen.kt`): ricerca, e per ciascuno le sue case.
struct HostsView: View {
    let model: CasesModel
    let onBack: () -> Void
    let onOpenCase: (String) -> Void

    @State private var query = ""
    @State private var selectedUid: String?

    var body: some View {
        let selected = model.hosts.first { $0.uid == selectedUid }
        VStack(spacing: 0) {
            CompactTopBar(title: selected.map(hostName) ?? "Host", onBack: {
                if selected != nil { selectedUid = nil } else { onBack() }
            })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    if let selected {
                        Text(selected.email.trimmed.isEmpty ? "Account non più presente" : selected.email)
                            .appStyle(.bodyMedium)
                            .foregroundStyle(Theme.onSurfaceVariant)
                        Button("Mostra solo le sue case") {
                            model.filter = .host(uid: selected.uid)
                            onBack()
                        }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity)
                        let cases = CaseLogic.sort(model.allSummaries.filter { $0.ownerUid == selected.uid })
                        ForEach(cases) { s in CaseCard(summary: s, hostLabel: nil) { onOpenCase(s.id) } }
                    } else {
                        AppTextField(label: "Cerca per email, nome o casa", text: $query, capitalization: .never)
                        let rows = CaseLogic.searchHosts(model.hosts, query: query)
                        if rows.isEmpty {
                            Text("Nessun host trovato.").appStyle(.bodyMedium).foregroundStyle(Theme.onSurfaceVariant)
                        }
                        ForEach(rows) { h in hostRow(h) }
                    }
                }
                .padding(Dimens.screenPadding)
            }
        }
    }

    private func hostRow(_ host: HostRow) -> some View {
        Button {
            selectedUid = host.uid
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(hostName(host))
                        .appStyle(.titleSmall)
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if host.pendingCount > 0 {
                        Text("\(host.pendingCount) da approvare")
                            .appStyle(.labelSmall)
                            .foregroundStyle(Theme.onSecondaryContainer)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(roundedShape(Radius.small).fill(Theme.secondaryContainer))
                    }
                }
                if !host.displayName.trimmed.isEmpty && !host.email.trimmed.isEmpty {
                    Text(host.email).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
                }
                Text("\(host.propertyCount) \(host.propertyCount == 1 ? "casa" : "case")")
                    .appStyle(.bodySmall)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            .padding(Dimens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
