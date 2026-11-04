import SwiftUI

// MARK: - Tabella Modifiche Prima / Dopo

public struct ChangesTable: View {
    public let changes: [Change]
    @State private var expandedKeys: Set<String> = []

    public init(changes: [Change]) {
        self.changes = changes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AssistantTexts.changesCaption)
                .font(.caption.bold())
                .foregroundStyle(Theme.onSurfaceVariant)
                .textCase(.uppercase)

            ForEach(changes, id: \.key) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.label)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.onSurface)

                    HStack(alignment: .top, spacing: 6) {
                        if change.before == nil {
                            Text(AssistantTexts.changesNew)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.primary.opacity(0.18)))
                                .foregroundStyle(Theme.primary)
                            renderValue(change.after, key: change.key, isLong: change.long)
                        } else if change.after == nil {
                            Text(AssistantTexts.changesRemoved)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.error.opacity(0.18)))
                                .foregroundStyle(Theme.error)
                            renderValue(change.before, key: change.key, isLong: change.long)
                        } else {
                            renderValue(change.before, key: change.key, isLong: change.long)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .padding(.top, 2)
                            renderValue(change.after, key: change.key, isLong: change.long)
                        }
                    }
                }
                .padding(.vertical, 4)
                if change.key != changes.last?.key {
                    Divider()
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.surfaceContainerHighest.opacity(0.5))
        }
    }

    @ViewBuilder
    private func renderValue(_ text: String?, key: String, isLong: Bool) -> some View {
        if let val = text {
            if isLong {
                let isExpanded = expandedKeys.contains(key)
                let trunc = truncateText(val)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isExpanded ? val : trunc.short)
                        .font(.caption)
                        .foregroundStyle(Theme.onSurface)
                    if trunc.truncated {
                        Button(isExpanded ? AssistantTexts.changesShowLess : AssistantTexts.changesShowAll) {
                            if isExpanded {
                                expandedKeys.remove(key)
                            } else {
                                expandedKeys.insert(key)
                            }
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.primary)
                    }
                }
            } else {
                Text(val)
                    .font(.caption)
                    .foregroundStyle(Theme.onSurface)
            }
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(Theme.onSurfaceVariant)
        }
    }
}

// MARK: - Scheda Proposta Singola

public struct ProposalCard: View {
    public let proposal: ProposalView
    public let onConfirm: () -> Void
    public let onUndo: () -> Void
    public let onDecline: () -> Void

    public init(
        proposal: ProposalView,
        onConfirm: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.proposal = proposal
        self.onConfirm = onConfirm
        self.onUndo = onUndo
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Intestazione proposta
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.primary)
                Text(proposal.ref.summary)
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer()
            }

            // Motivo
            if let reason = proposal.ref.reason {
                Text(AssistantTexts.proposalReason(reason))
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Theme.onSurfaceVariant)
            }

            // Avvisi
            ForEach(proposal.ref.warnings, id: \.self) { warn in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.secondary)
                    Text(warn)
                        .font(.caption)
                        .foregroundStyle(Theme.onSurface)
                }
            }

            // Tabella prima / dopo se presente
            if let changes = proposal.appliedChanges ?? proposal.ref.changes, !changes.isEmpty {
                ChangesTable(changes: changes)
            }

            // Stato e pulsanti di azione
            switch proposal.status {
            case .pending:
                HStack(spacing: 12) {
                    Button(AssistantTexts.confirm) {
                        onConfirm()
                    }
                    .buttonStyle(AppPrimaryButtonStyle())

                    Button(AssistantTexts.decline) {
                        onDecline()
                    }
                    .buttonStyle(AppOutlinedButtonStyle())
                }
                .padding(.top, 4)

            case .busy:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(AssistantTexts.busy)
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }

            case .done:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.primary)
                        Text(proposal.result ?? AssistantTexts.done)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.primary)
                    }

                    // Pulsante Annulla con timer conto alla rovescia
                    if let undoUntil = proposal.undoUntil {
                        let msLeft = undoUntil - Int64(Date().timeIntervalSince1970 * 1000)
                        if msLeft > 0 {
                            Button {
                                onUndo()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("\(AssistantTexts.undo) · \(formatCountdown(ms: msLeft))")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Theme.error)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().stroke(Theme.error.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let err = proposal.undoError {
                        Text(AssistantTexts.undoErrorText(err))
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }

            case .declined:
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Theme.onSurfaceVariant)
                    Text(AssistantTexts.declined)
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }

            case .error:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.error)
                        Text(proposal.errorText ?? AssistantTexts.errorText(proposal.error ?? .generic))
                            .font(.subheadline)
                            .foregroundStyle(Theme.error)
                    }
                    Button(AssistantTexts.confirm) {
                        onConfirm()
                    }
                    .buttonStyle(AppOutlinedButtonStyle())
                }

            case .undoing:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(AssistantTexts.undoing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }

            case .undone:
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(Theme.onSurfaceVariant)
                    Text(proposal.result ?? AssistantTexts.undoneWith)
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surfaceContainerHigh.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outlineVariant.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - Gruppo di Proposte Multiple

public struct ProposalGroupView: View {
    public let proposals: [ProposalView]
    public let onConfirmMany: () -> Void
    public let onDeclineMany: () -> Void
    public let onConfirmSingle: (String) -> Void
    public let onUndoSingle: (String) -> Void
    public let onDeclineSingle: (String) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let pendingCount = proposals.filter { $0.status == .pending }.count

            if pendingCount > 1 {
                HStack(spacing: 12) {
                    Button(AssistantTexts.confirmSelected(pendingCount)) {
                        onConfirmMany()
                    }
                    .buttonStyle(AppPrimaryButtonStyle())

                    Button(AssistantTexts.declineSelected) {
                        onDeclineMany()
                    }
                    .buttonStyle(AppOutlinedButtonStyle())
                }
                .padding(.bottom, 4)
            }

            ForEach(proposals, id: \.ref.id) { prop in
                ProposalCard(
                    proposal: prop,
                    onConfirm: { onConfirmSingle(prop.ref.id) },
                    onUndo: { onUndoSingle(prop.ref.id) },
                    onDecline: { onDeclineSingle(prop.ref.id) }
                )
            }
        }
    }
}
