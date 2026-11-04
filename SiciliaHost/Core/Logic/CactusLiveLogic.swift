import Foundation

/// Opacità del velo quando Cactus sta lavorando: scende dal 38% al 18% per lasciar leggere bene l'app sotto.
public let veilWorkAlpha: Float = 0.18

public enum LivePhase: Equatable, Sendable {
    case idle
    case running
    case finishing
}

public enum LiveMode: Equatable, Sendable {
    case do_
    case undo
}

public enum StageKind: Equatable, Sendable {
    case opening
    case writing
    case saving
    case flashing
}

public struct LiveStage: Equatable, Sendable {
    public let kind: StageKind
    public let section: LiveSection
    public let propertyId: String
    public let key: String?
    public let label: String?
    public let before: String?
    public let after: String?
    public var progress: Float

    public init(
        kind: StageKind,
        section: LiveSection,
        propertyId: String,
        key: String? = nil,
        label: String? = nil,
        before: String? = nil,
        after: String? = nil,
        progress: Float = 0.0
    ) {
        self.kind = kind
        self.section = section
        self.propertyId = propertyId
        self.key = key
        self.label = label
        self.before = before
        self.after = after
        self.progress = progress
    }
}

public struct LiveState: Equatable, Sendable {
    public var phase: LivePhase = .idle
    public var mode: LiveMode = .do_
    public var stepText: String = ""
    public var stage: LiveStage? = nil
    public var activeChanges: [Change] = []
    public var activeKey: String? = nil
    public var stopRequested: Bool = false

    public var isActive: Bool {
        phase != .idle
    }

    public init(
        phase: LivePhase = .idle,
        mode: LiveMode = .do_,
        stepText: String = "",
        stage: LiveStage? = nil,
        activeChanges: [Change] = [],
        activeKey: String? = nil,
        stopRequested: Bool = false
    ) {
        self.phase = phase
        self.mode = mode
        self.stepText = stepText
        self.stage = stage
        self.activeChanges = activeChanges
        self.activeKey = activeKey
        self.stopRequested = stopRequested
    }
}

public enum LiveAction: Equatable, Sendable {
    case start(mode: LiveMode, stepText: String)
    case step(stepText: String, stage: LiveStage?, activeChanges: [Change]?, activeKey: String?)
    case progress(Float)
    case requestStop
    case finish(stepText: String, stage: LiveStage?)
    case reset
}

public func liveReducer(state: LiveState, action: LiveAction) -> LiveState {
    switch action {
    case .start(let mode, let stepText):
        return LiveState(
            phase: .running,
            mode: mode,
            stepText: stepText
        )

    case .step(let stepText, let stage, let activeChanges, let activeKey):
        if state.phase == .idle { return state }
        var copy = state
        copy.stepText = stepText
        copy.stage = stage
        if let changes = activeChanges { copy.activeChanges = changes }
        copy.activeKey = activeKey
        return copy

    case .progress(let p):
        if state.phase != .running || state.stage == nil { return state }
        var copy = state
        if var s = copy.stage {
            s.progress = min(max(p, 0.0), 1.0)
            copy.stage = s
        }
        return copy

    case .requestStop:
        if state.phase != .running { return state }
        var copy = state
        copy.stopRequested = true
        return copy

    case .finish(let stepText, let stage):
        if state.phase == .idle { return state }
        var copy = state
        copy.phase = .finishing
        copy.stepText = stepText
        copy.stage = stage
        copy.stopRequested = false
        return copy

    case .reset:
        return LiveState()
    }
}

// MARK: - Durate e Interpolazione dei Valori

public func fieldDuration(count: Int, valueLength: Int) -> Int64 {
    if count <= 0 { return 0 }
    let base: Int64
    if count == 1 {
        base = 520
    } else if count <= 4 {
        base = 320
    } else {
        base = max(140, 1_400 / Int64(count))
    }
    let extra = valueLength > 60 ? min(450, Int64(valueLength - 60) * 3) : 0
    return base + extra
}

public func typedText(_ text: String, progress: Float) -> String {
    if progress <= 0 || text.isEmpty { return "" }
    if progress >= 1.0 { return text }
    let n = max(1, Int(Float(text.count) * progress))
    return typedPrefix(text: text, n: n)
}

private let numberRegex = try! NSRegularExpression(pattern: "^-?\\d+(?:[.,]\\d+)?")

public func countedText(before: String?, after: String?, progress: Float) -> String {
    guard let after = after else { return "" }
    if progress >= 1.0 { return after }
    if progress <= 0.0 { return before ?? "" }

    let bTrim = before?.trimmingCharacters(in: .whitespaces)
    let aTrim = after.trimmingCharacters(in: .whitespaces)

    let bMatch = bTrim.flatMap { str -> String? in
        let range = NSRange(location: 0, length: str.utf16.count)
        guard let m = numberRegex.firstMatch(in: str, options: [], range: range),
              let r = Range(m.range, in: str) else { return nil }
        return String(str[r])
    }
    let aMatch: String? = {
        let range = NSRange(location: 0, length: aTrim.utf16.count)
        guard let m = numberRegex.firstMatch(in: aTrim, options: [], range: range),
              let r = Range(m.range, in: aTrim) else { return nil }
        return String(aTrim[r])
    }()

    if let bStr = bMatch, let aStr = aMatch {
        let bVal = Double(bStr.replacingOccurrences(of: ",", with: "."))
        let aVal = Double(aStr.replacingOccurrences(of: ",", with: "."))

        if let bNum = bVal, let aNum = aVal, bNum.isFinite, aNum.isFinite {
            let current = bNum + (aNum - bNum) * Double(min(max(progress, 0.0), 1.0))
            let decimals: Int
            if let dotIdx = aStr.firstIndex(of: ".") ?? aStr.firstIndex(of: ",") {
                decimals = aStr.distance(from: aStr.index(after: dotIdx), to: aStr.endIndex)
            } else {
                decimals = 0
            }
            let useComma = aStr.contains(",") || (bTrim?.contains(",") ?? false)
            let formatted = String(format: "%.\(decimals)f", current)
            let numStr = useComma ? formatted.replacingOccurrences(of: ".", with: ",") : formatted
            let tail = String(aTrim.dropFirst(aStr.count))
            return numStr + tail
        }
    }

    return typedText(after, progress: progress)
}

public func invertChanges(_ changes: [Change]) -> [Change] {
    return changes.map { Change(key: $0.key, label: $0.label, before: $0.after, after: $0.before, long: $0.long) }
}

public func mergePlans(_ plans: [[LiveStep]]) -> [LiveStep] {
    var dict: [String: (LiveSection, String, [String])] = [:]
    var order: [String] = []

    for plan in plans {
        for step in plan {
            let id = "\(step.section.rawValue)__\(step.propertyId)"
            if dict[id] == nil {
                order.append(id)
                dict[id] = (step.section, step.propertyId, step.keys)
            } else {
                var existing = dict[id]!.2
                for k in step.keys {
                    if !existing.contains(k) {
                        existing.append(k)
                    }
                }
                dict[id] = (step.section, step.propertyId, existing)
            }
        }
    }

    return order.compactMap { id -> LiveStep? in
        guard let entry = dict[id] else { return nil }
        return LiveStep(section: entry.0, propertyId: entry.1, keys: entry.2)
    }
}

// MARK: - Mappatura Verso l'App iOS

public struct LiveAppTarget: Equatable, Sendable {
    public let tab: MainTab
    public let propertyId: String?
    public let caseSection: CaseSection?
    public let caseSub: CaseSubEditor?

    public init(
        tab: MainTab,
        propertyId: String? = nil,
        caseSection: CaseSection? = nil,
        caseSub: CaseSubEditor? = nil
    ) {
        self.tab = tab
        self.propertyId = propertyId
        self.caseSection = caseSection
        self.caseSub = caseSub
    }
}

public func liveTargetFor(step: LiveStep) -> LiveAppTarget {
    let propId = step.propertyId.isEmpty ? nil : step.propertyId
    switch step.section {
    case .overview:
        return LiveAppTarget(tab: .home)
    case .calendar:
        return LiveAppTarget(tab: .agenda, propertyId: propId)
    case .finance:
        return LiveAppTarget(tab: .finanze, propertyId: propId)
    case .inventory:
        return LiveAppTarget(tab: .scorte, propertyId: propId)
    case .prices:
        return LiveAppTarget(tab: .case_, propertyId: propId, caseSection: .prezzi)
    case .conditions:
        let keys = step.keys
        let sec: CaseSection
        if keys.contains(where: { $0.hasPrefix("checkin.") || $0.hasPrefix("checkout.") }) {
            sec = .orari
        } else if keys.contains("CIN") {
            sec = .informazioni
        } else if keys.contains(where: { $0.hasPrefix("rules.") || $0.hasPrefix("parking.") || $0.hasPrefix("touristTax.") }) {
            sec = .contenuti
        } else {
            sec = .prezzi
        }
        return LiveAppTarget(tab: .case_, propertyId: propId, caseSection: sec)
    case .texts:
        let keys = step.keys
        let sec: CaseSection
        if keys.contains(where: { $0.hasSuffix(".en") || $0.hasSuffix(".fr") || $0.hasSuffix(".pl") }) {
            sec = .infoOspiti
        } else if keys.contains(where: { $0.hasPrefix("text.rules") }) {
            sec = .orari
        } else {
            sec = .informazioni
        }
        return LiveAppTarget(tab: .case_, propertyId: propId, caseSection: sec)
    case .services:
        return LiveAppTarget(tab: .case_, propertyId: propId, caseSection: .contenuti, caseSub: .services)
    case .guestInfo:
        let sec: CaseSection = step.keys.contains("info.zone") ? .posizione : .infoOspiti
        return LiveAppTarget(tab: .case_, propertyId: propId, caseSection: sec)
    }
}
