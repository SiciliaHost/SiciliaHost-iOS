import SwiftUI

public struct ConsentView: View {
    public let state: ConsentState
    public let onAccept: () -> Void
    public let onDecline: () -> Void

    public init(state: ConsentState, onAccept: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.state = state
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Theme.primary)
                Text(AssistantTexts.consentTitle)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.onSurface)
            }

            Text(AssistantTexts.consentIntro)
                .font(.body)
                .foregroundStyle(Theme.onSurfaceVariant)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AssistantTexts.consentPoints, id: \.0) { point in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.0)
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.onSurface)
                            Text(point.1)
                                .font(.caption)
                                .foregroundStyle(Theme.onSurfaceVariant)
                        }
                    }

                    Link(destination: LegalLinks.privacy) {
                        HStack(spacing: 4) {
                            Text(AssistantTexts.consentPrivacy)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Theme.primary)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)

            if state.failed {
                Text(AssistantTexts.consentFailed)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }

            HStack(spacing: 12) {
                if state.busy {
                    ProgressView()
                    Text(AssistantTexts.busy)
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceVariant)
                } else {
                    Button(AssistantTexts.consentAccept) {
                        onAccept()
                    }
                    .buttonStyle(AppPrimaryButtonStyle())

                    Button(AssistantTexts.consentDecline) {
                        onDecline()
                    }
                    .buttonStyle(AppOutlinedButtonStyle())
                }
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceContainerHigh)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.outlineVariant, lineWidth: 1))
                .softShadow(12)
        }
    }
}
