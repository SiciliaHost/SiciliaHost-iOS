import SwiftUI

/// «Check-in inviato» sulle prenotazioni con il segno `checkin` (Home, Agenda), come `CheckinSentLabel.kt`.
struct CheckinSentLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text("Check-in inviato").appStyle(.labelSmall)
        }
        .foregroundStyle(Theme.primary)
        .accessibilityElement(children: .combine)
    }
}
