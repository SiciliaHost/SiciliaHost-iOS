import SwiftUI

/// Per ora mostra solo le case dell'utente (verifica end-to-end di login + accesso).
/// TODO F4: porting di `ui/dashboard` (prenotazioni di oggi, da completare, check-in).
struct HomeView: View {
    let scope: AccessScope?
    let onProfile: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Dimens.sectionSpacing) {
                ZStack {
                    BrandLogo(height: 72)
                    HStack {
                        Spacer()
                        Button(action: onProfile) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 26))
                        }
                        .buttonStyle(.appIcon)
                        .tourTarget(.profile)
                        .accessibilityLabel("Profilo")
                    }
                }
                .padding(.top, Dimens.itemSpacing)

                VStack(alignment: .leading, spacing: Dimens.itemSpacing) {
                    SectionLabel(scope?.profileLabel ?? "")
                    ForEach(scope?.properties ?? []) { property in
                        HStack(spacing: 10) {
                            Image(systemName: "house.fill")
                                .font(.system(size: Dimens.iconSmall))
                                .foregroundStyle(Theme.primary)
                                .frame(width: Dimens.iconMedium, height: Dimens.iconMedium)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(property.name).appStyle(.titleMedium).foregroundStyle(Theme.onSurface)
                                if let scope, !scope.canOperate(property) {
                                    Text("SOLO VISIBILE").appStyle(.labelSmall).foregroundStyle(Theme.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Dimens.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                    }
                }
            }
            .padding(Dimens.screenPadding)
        }
    }
}
