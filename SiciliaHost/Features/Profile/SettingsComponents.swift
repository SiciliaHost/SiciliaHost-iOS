import SwiftUI

// Componenti delle impostazioni (`SettingsGroup`, `SettingsRow`, `CollaboratorsCard` di `ProfileScreen.kt`).

/// Una voce di impostazioni: icona (SF Symbol), titolo, descrizione opzionale.
struct SettingsItem {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var enabled = true
    let action: () -> Void
}

/// Una categoria: occhiello e, sotto, una sola scheda con le voci separate da una linea sottile.
struct SettingsGroup: View {
    let title: String
    let items: [SettingsItem]
    var emptyText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
            SectionLabel(title).padding(.top, Dimens.itemSpacing)
            if items.isEmpty {
                if let emptyText {
                    Text(emptyText).appStyle(.bodyMedium).foregroundStyle(Theme.onSurface)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().padding(.leading, Dimens.cardPadding + Dimens.iconMedium + 12)
                        }
                        SettingsRow(item: items[index])
                    }
                }
                .appCard()
            }
        }
    }
}

struct SettingsRow: View {
    let item: SettingsItem

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: Dimens.iconSmall + 2, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(width: Dimens.iconMedium)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).appStyle(.bodyLarge).foregroundStyle(Theme.onSurface).lineLimit(2)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle).appStyle(.bodySmall).foregroundStyle(Theme.onSurfaceVariant).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: Dimens.iconSmall - 4, weight: .semibold))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(Dimens.cardPadding)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
    }
}

/// La funzione Collaboratori, evidenziata in cima alle impostazioni; apre il suo sottomenù.
struct CollaboratorsCard: View {
    let summary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: Dimens.iconSmall + 4, weight: .medium))
                    .foregroundStyle(Theme.onPrimaryContainer)
                    .frame(width: Dimens.iconMedium)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Collaboratori").appStyle(.titleMedium).foregroundStyle(Theme.onPrimaryContainer)
                    Text(summary).appStyle(.bodySmall).foregroundStyle(Theme.onPrimaryContainer).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: Dimens.iconSmall - 4, weight: .semibold))
                    .foregroundStyle(Theme.onPrimaryContainer)
                    .accessibilityHidden(true)
            }
            .padding(Dimens.cardPadding)
            .frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Theme.primaryContainer))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
