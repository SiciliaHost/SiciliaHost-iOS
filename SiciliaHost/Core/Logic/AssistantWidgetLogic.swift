import Foundation

// MARK: - Quale widget è attivo (Spec §3.5)

/// Un widget è attivo solo nell'ultimo messaggio di Cactus, se dopo non c'è un messaggio dell'host (le note locali
/// non contano) e finché non c'è un invio in corso o un consenso aperto (`blocked`).
public func activeWidgetMessageId(messages: [ChatMessage], blocked: Bool) -> Int? {
    if blocked { return nil }
    guard let last = messages.last(where: { $0.role != .note }) else { return nil }
    return (last.role == .assistant && !last.widgets.isEmpty) ? last.id : nil
}

// MARK: - Validazione Giorni e Date

/// Vero se il giorno è fuori da min/max o dentro un blocco `disabled` (estremi inclusi). Le date ISO si confrontano come testo.
public func isDayDisabled(day: String, w: DatesWidget) -> Bool {
    if let min = w.min, day < min { return true }
    if let max = w.max, day > max { return true }
    return w.disabled.contains { $0.from <= day && day <= $0.to }
}

/// Un intervallo è valido se la fine non precede l'inizio, sta dentro min/max e nessun giorno al suo interno è disabilitato.
public func rangeIsValid(start: String, end: String, w: DatesWidget) -> Bool {
    if end < start { return false }
    if let min = w.min, start < min { return false }
    if let max = w.max, end > max { return false }
    return !w.disabled.contains { $0.from <= end && start <= $0.to }
}

/// Il giorno da cui parte il calendario: `today`, portato dentro min e max.
public func initialDay(w: DatesWidget, today: String) -> String {
    var day = today
    if let min = w.min, day < min { day = min }
    if let max = w.max, day > max { day = max }
    return day
}

private let isoDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.locale = Locale(identifier: "en_US_POSIX")
    return df
}()

/// Mezzanotte UTC del giorno `YYYY-MM-DD`.
public func isoToUtcMillis(_ iso: String) -> Int64 {
    guard let date = isoDateFormatter.date(from: iso) else { return 0 }
    return Int64(date.timeIntervalSince1970 * 1000)
}

/// Il giorno `YYYY-MM-DD` (UTC) di un istante espresso in millisecondi.
public func utcMillisToIso(_ millis: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
    return isoDateFormatter.string(from: date)
}

// MARK: - Formattazione Lingua e Testi

private func localeOf(language: String) -> Locale {
    switch language {
    case "en": return Locale(identifier: "en_GB")
    case "fr": return Locale(identifier: "fr_FR")
    case "pl": return Locale(identifier: "pl_PL")
    default: return Locale(identifier: "it_IT")
    }
}

private func isItalian(_ language: String) -> Bool {
    return language == "it" || !assistantLanguages.contains(language)
}

/// «14 agosto 2026» nella lingua data.
public func formatLongDate(_ iso: String, language: String) -> String {
    guard let date = isoDateFormatter.date(from: iso) else { return iso }
    let df = DateFormatter()
    df.dateFormat = "d MMMM yyyy"
    df.locale = localeOf(language: language)
    df.timeZone = TimeZone(secondsFromGMT: 0)
    return df.string(from: date)
}

/// «dal 14 al 18 agosto 2026»: stesso mese -> «14» e «18 agosto 2026»; stesso anno -> «28 agosto» e «3 settembre 2026».
public func dateRangeParts(from: String, to: String, language: String) -> (String, String) {
    guard let fromDate = isoDateFormatter.date(from: from),
          let toDate = isoDateFormatter.date(from: to) else {
        return (from, to)
    }
    let loc = localeOf(language: language)
    let tz = TimeZone(secondsFromGMT: 0)!

    if from.prefix(7) == to.prefix(7) {
        let dfDay = DateFormatter()
        dfDay.dateFormat = "d"
        dfDay.locale = loc
        dfDay.timeZone = tz
        return (dfDay.string(from: fromDate), formatLongDate(to, language: language))
    } else if from.prefix(4) == to.prefix(4) {
        let dfShort = DateFormatter()
        dfShort.dateFormat = "d MMMM"
        dfShort.locale = loc
        dfShort.timeZone = tz
        return (dfShort.string(from: fromDate), formatLongDate(to, language: language))
    } else {
        return (formatLongDate(from, language: language), formatLongDate(to, language: language))
    }
}

/// Numeri senza separatore delle migliaia, con virgola o punto della lingua.
public func formatAmountNumber(_ value: Double, language: String, fixed: Bool) -> String {
    let nf = NumberFormatter()
    nf.locale = localeOf(language: language)
    nf.usesGroupingSeparator = false
    nf.minimumFractionDigits = fixed ? 2 : 0
    nf.maximumFractionDigits = 2
    return nf.string(from: NSNumber(value: value)) ?? String(value)
}

// MARK: - Testi Risposte dell'Host

public func replyChoice(labels: [String], language: String) -> String {
    let isIt = isItalian(language)
    if labels.count == 1 {
        return (isIt ? "Scelto: " : "Chosen: ") + labels[0]
    } else {
        return (isIt ? "Scelte: " : "Chosen: ") + labels.joined(separator: "; ")
    }
}

public func replyDates(from: String, to: String?, language: String) -> String {
    let isIt = isItalian(language)
    if to == nil || to == from {
        return (isIt ? "Data scelta: " : "Chosen date: ") + formatLongDate(from, language: language)
    }
    let parts = dateRangeParts(from: from, to: to!, language: language)
    let prefix = isIt ? "Date scelte: dal " : "Chosen dates: from "
    let middle = isIt ? " al " : " to "
    return prefix + parts.0 + middle + parts.1
}

public func replyAmount(value: Double, w: AmountWidget, language: String) -> String {
    let isIt = isItalian(language)
    let isEuro = (w.kind == .euro)
    let formatted = formatAmountNumber(value, language: language, fixed: isEuro)
    let unit = w.unit ?? (isEuro ? "€" : "")
    if isEuro {
        return (isIt ? "Importo: " : "Amount: ") + formatted + " €"
    } else {
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return (isIt ? "Quantità: " : "Quantity: ") + formatted + suffix
    }
}

// MARK: - Validazione Importo

public enum AmountError: Equatable, Sendable {
    case empty
    case format
    case decimals
    case min
    case max
}

public let amountHardMax: Double = 1_000_000.0

public func parseAndValidateAmount(_ raw: String, w: AmountWidget) -> Result<Double, AmountError> {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .failure(.empty) }

    // Sostituisce la virgola col punto per parsing sicuro
    let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value.isFinite else {
        return .failure(.format)
    }

    // Controllo decimali
    if let dotIndex = normalized.firstIndex(of: ".") {
        let decimals = normalized[normalized.index(after: dotIndex)...]
        if decimals.count > 2 {
            return .failure(.decimals)
        }
    }

    if let min = w.min, value < min {
        return .failure(.min)
    }
    let effectiveMax = w.max ?? amountHardMax
    if value > effectiveMax {
        return .failure(.max)
    }

    return .success(value)
}

// MARK: - Payload e Parser Callable

/// Costruisce il dizionario payload per `assistantMessage`.
public func buildMessagePayload(
    text: String,
    conversationId: String?,
    locale: String,
    propertyId: String?,
    selection: [String]?
) -> [String: Any] {
    var payload: [String: Any] = [
        "message": text,
        "locale": locale,
        "supportsWidgets": true
    ]
    if let conversationId = conversationId, !conversationId.isEmpty {
        payload["conversationId"] = conversationId
    }
    if let propertyId = propertyId, !propertyId.isEmpty {
        payload["propertyId"] = propertyId
    }
    if let validSelection = sanitizeSelection(selection) {
        payload["selection"] = ["ids": validSelection]
    }
    return payload
}

public func parseAvailable(_ data: Any?) -> Bool {
    if let boolVal = data as? Bool { return boolVal }
    if let dict = data as? [String: Any], let avail = dict["available"] as? Bool { return avail }
    return false
}

public func parseMessageResult(_ data: Any?) -> MessageResult? {
    guard let dict = data as? [String: Any] else { return nil }
    guard let conversationId = dict["conversationId"] as? String,
          let reply = dict["reply"] as? String,
          let remainingToday = dict["remainingToday"] as? Int else {
        return nil
    }

    var proposals: [ProposalRef] = []
    if let propList = dict["proposals"] as? [[String: Any]] {
        for pDict in propList {
            if let p = parseProposal(pDict) {
                proposals.append(p)
            }
        }
    }

    let widgets = parseWidgets(dict["widgets"])

    return MessageResult(
        conversationId: conversationId,
        reply: reply,
        proposals: proposals,
        remainingToday: remainingToday,
        widgets: widgets
    )
}

public func parseProposal(_ dict: [String: Any]) -> ProposalRef? {
    guard let id = dict["id"] as? String,
          let tool = dict["tool"] as? String,
          let propertyId = dict["propertyId"] as? String,
          let summary = dict["summary"] as? String else {
        return nil
    }

    let warnings = dict["warnings"] as? [String] ?? []
    let expiresAt: Int64
    if let num = dict["expiresAt"] as? NSNumber {
        expiresAt = num.int64Value
    } else {
        expiresAt = 0
    }

    let reason = dict["reason"] as? String

    var changes: [Change]? = nil
    if let rawChanges = dict["changes"] as? [[String: Any]] {
        var parsedChanges: [Change] = []
        var malformed = false
        for cDict in rawChanges {
            guard let key = cDict["key"] as? String, !key.isEmpty,
                  let label = cDict["label"] as? String, !label.isEmpty else {
                malformed = true
                break
            }
            let before = cDict["before"] as? String
            let after = cDict["after"] as? String
            let long = cDict["long"] as? Bool ?? false
            parsedChanges.append(Change(key: key, label: label, before: before, after: after, long: long))
        }
        if !malformed {
            changes = parsedChanges
        }
    }

    var plan: [LiveStep]? = nil
    if let rawPlan = dict["plan"] as? [[String: Any]] {
        var parsedPlan: [LiveStep] = []
        var malformed = false
        for sDict in rawPlan {
            guard let sectionStr = sDict["section"] as? String,
                  let section = LiveSection.fromWire(sectionStr),
                  let propId = sDict["propertyId"] as? String, !propId.isEmpty,
                  let keys = sDict["keys"] as? [String], !keys.isEmpty else {
                malformed = true
                break
            }
            parsedPlan.append(LiveStep(section: section, propertyId: propId, keys: keys))
        }
        if !malformed {
            plan = parsedPlan
        }
    }

    return ProposalRef(
        id: id,
        tool: tool,
        propertyId: propertyId,
        summary: summary,
        warnings: warnings,
        expiresAt: expiresAt,
        changes: changes,
        plan: plan,
        reason: reason
    )
}

public func parseWidgets(_ data: Any?) -> [AnyWidget] {
    guard let list = data as? [Any] else { return [] }
    var widgets: [AnyWidget] = []
    for item in list {
        if let dict = item as? [String: Any], let w = parseWidget(dict) {
            widgets.append(w)
        }
    }
    return widgets
}

public func parseWidget(_ dict: [String: Any]) -> AnyWidget? {
    guard let type = dict["type"] as? String,
          let id = dict["id"] as? String, !id.isEmpty else {
        return nil
    }

    switch type {
    case "choice":
        guard let prompt = dict["prompt"] as? String,
              let rawOptions = dict["options"] as? [[String: Any]], !rawOptions.isEmpty else {
            return nil
        }
        var options: [ChoiceOption] = []
        for opt in rawOptions {
            guard let optId = opt["id"] as? String, !optId.isEmpty,
                  let label = opt["label"] as? String, !label.isEmpty else {
                return nil
            }
            let detail = opt["detail"] as? String
            options.append(ChoiceOption(id: optId, label: label, detail: detail))
        }
        let multiple = dict["multiple"] as? Bool ?? false
        return .choice(ChoiceWidget(id: id, prompt: prompt, multiple: multiple, options: options))

    case "dates":
        guard let prompt = dict["prompt"] as? String,
              let modeStr = dict["mode"] as? String,
              let mode = DatesMode(rawValue: modeStr) else {
            return nil
        }
        let min = dict["min"] as? String
        if let min = min, isoDateFormatter.date(from: min) == nil { return nil }
        let max = dict["max"] as? String
        if let max = max, isoDateFormatter.date(from: max) == nil { return nil }

        var disabled: [DateRange] = []
        if let rawDisabled = dict["disabled"] as? [[String: Any]] {
            for d in rawDisabled {
                guard let from = d["from"] as? String, isoDateFormatter.date(from: from) != nil,
                      let to = d["to"] as? String, isoDateFormatter.date(from: to) != nil else {
                    return nil
                }
                disabled.append(DateRange(from: from, to: to))
            }
        }
        return .dates(DatesWidget(id: id, prompt: prompt, mode: mode, min: min, max: max, disabled: disabled))

    case "quick_replies":
        guard let rawOptions = dict["options"] as? [[String: Any]], !rawOptions.isEmpty else {
            return nil
        }
        var options: [QuickReply] = []
        for opt in rawOptions {
            guard let label = opt["label"] as? String, !label.isEmpty,
                  let text = opt["text"] as? String, !text.isEmpty else {
                return nil
            }
            options.append(QuickReply(label: label, text: text))
        }
        return .quickReplies(QuickRepliesWidget(id: id, options: options))

    case "summary":
        guard let title = dict["title"] as? String,
              let rawRows = dict["rows"] as? [[String: Any]] else {
            return nil
        }
        var rows: [SummaryRow] = []
        for r in rawRows {
            guard let label = r["label"] as? String,
                  let value = r["value"] as? String else {
                return nil
            }
            let emphasis = r["emphasis"] as? Bool ?? false
            rows.append(SummaryRow(label: label, value: value, emphasis: emphasis))
        }
        let note = dict["note"] as? String
        return .summary(SummaryWidget(id: id, title: title, rows: rows, note: note))

    case "amount":
        guard let prompt = dict["prompt"] as? String,
              let kindStr = dict["kind"] as? String,
              let kind = AmountKind(rawValue: kindStr) else {
            return nil
        }
        var suggestions: [Double] = []
        if let rawSugg = dict["suggestions"] as? [Any] {
            for s in rawSugg {
                if let num = s as? NSNumber {
                    suggestions.append(num.doubleValue)
                } else {
                    return nil
                }
            }
        }
        let min = (dict["min"] as? NSNumber)?.doubleValue
        let max = (dict["max"] as? NSNumber)?.doubleValue
        let defaultValue = (dict["defaultValue"] as? NSNumber)?.doubleValue
        let unit = dict["unit"] as? String
        return .amount(AmountWidget(
            id: id,
            prompt: prompt,
            kind: kind,
            suggestions: suggestions,
            min: min,
            max: max,
            defaultValue: defaultValue,
            unit: unit
        ))

    default:
        return nil
    }
}

public func parseConfirmResult(_ data: Any?) -> ConfirmResult {
    guard let dict = data as? [String: Any],
          let summary = dict["summary"] as? String else {
        return ConfirmResult(summary: "Modifica completata.")
    }
    var changes: [Change] = []
    if let rawChanges = dict["changes"] as? [[String: Any]] {
        for cDict in rawChanges {
            if let key = cDict["key"] as? String,
               let label = cDict["label"] as? String {
                let before = cDict["before"] as? String
                let after = cDict["after"] as? String
                let long = cDict["long"] as? Bool ?? false
                changes.append(Change(key: key, label: label, before: before, after: after, long: long))
            }
        }
    }
    let undoUntil = (dict["undoUntil"] as? NSNumber)?.int64Value
    return ConfirmResult(summary: summary, changes: changes, undoUntil: undoUntil)
}

public func parseUndoResult(_ data: Any?) -> UndoResult {
    guard let dict = data as? [String: Any],
          let summary = dict["summary"] as? String else {
        return UndoResult(summary: "Modifica annullata.")
    }
    var changes: [Change] = []
    if let rawChanges = dict["changes"] as? [[String: Any]] {
        for cDict in rawChanges {
            if let key = cDict["key"] as? String,
               let label = cDict["label"] as? String {
                let before = cDict["before"] as? String
                let after = cDict["after"] as? String
                let long = cDict["long"] as? Bool ?? false
                changes.append(Change(key: key, label: label, before: before, after: after, long: long))
            }
        }
    }
    return UndoResult(summary: summary, changes: changes)
}
