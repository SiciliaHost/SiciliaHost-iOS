import XCTest
@testable import SiciliaHost

// Specifica: HostFunctionsParsersTest, InviteParsersTest, ListingRepositoryParseTest, ParseSeasonalRatesTest,
// PriceRepositoryParseTest dell'app Android.
final class CallableParsersTests: XCTestCase {
    // MARK: Inviti

    func testParseInviteReadsCodeAndExpiry() {
        XCTAssertEqual(parseInvite(["code": "ABCD2345", "expiresAt": 1_760_000_000_000] as [String: Any]), Invite(code: "ABCD2345", expiresAt: 1_760_000_000_000))
        // I numeri JSON arrivano come Int/Long/Double a seconda della grandezza.
        XCTAssertEqual(parseInvite(["code": "X", "expiresAt": 5.0] as [String: Any])?.expiresAt, 5)
    }

    func testParseInviteRejectsMalformedData() {
        XCTAssertNil(parseInvite(nil))
        XCTAssertNil(parseInvite(["code": "X"]))
        XCTAssertNil(parseInvite(["expiresAt": 1]))
    }

    func testParseInvitePreviewReadsEverything() {
        let preview = parseInvitePreview([
            "code": "ABCD2345", "expiresAt": 1_760_000_000_000, "inviterEmail": "boss@example.com",
            "grants": [
                ["propertyId": "p1", "propertyName": "Casa Mare", "permissions": ["PRICES", "FINANCE"]],
                ["propertyId": "p2", "propertyName": "Casa Monte", "permissions": [String]()],
            ],
        ] as [String: Any])
        XCTAssertEqual(preview, InvitePreview(
            code: "ABCD2345", expiresAt: 1_760_000_000_000, inviterEmail: "boss@example.com",
            grants: [
                InvitePreviewGrant(propertyId: "p1", propertyName: "Casa Mare", permissions: [.prices, .finance]),
                InvitePreviewGrant(propertyId: "p2", propertyName: "Casa Monte", permissions: []),
            ]
        ))
    }

    func testParseInvitePreviewIgnoresUnknownPermissionsAndBrokenGrants() {
        let preview = parseInvitePreview([
            "code": "X", "expiresAt": 5.0, "inviterEmail": "a@b.c",
            "grants": [
                ["propertyId": "p1", "propertyName": "Casa", "permissions": ["SITE", "ROOT", 3]] as [String: Any],
                ["propertyName": "senza id"],
                "boh",
            ] as [Any],
        ] as [String: Any])
        XCTAssertEqual(preview?.grants, [InvitePreviewGrant(propertyId: "p1", propertyName: "Casa", permissions: [.site])])
        XCTAssertEqual(preview?.expiresAt, 5)
    }

    func testParseInvitePreviewMissingFields() {
        XCTAssertNil(parseInvitePreview(nil))
        XCTAssertNil(parseInvitePreview(["expiresAt": 1, "grants": [Any]()] as [String: Any]))
        XCTAssertNil(parseInvitePreview(["code": "X", "grants": [Any]()] as [String: Any]))
        XCTAssertEqual(parseInvitePreview(["code": "X", "expiresAt": 1] as [String: Any]),
                       InvitePreview(code: "X", expiresAt: 1, inviterEmail: "", grants: []))
        XCTAssertEqual(
            parseInvitePreview(["code": "X", "expiresAt": 1, "grants": [["propertyId": "p1"]]] as [String: Any])?.grants,
            [InvitePreviewGrant(propertyId: "p1", propertyName: "", permissions: [])]
        )
    }

    func testParseRedeemResult() {
        XCTAssertEqual(parseRedeemResult(["propertyIds": ["p1", "p2"], "propertyId": "p1"] as [String: Any]), ["p1", "p2"])
        XCTAssertEqual(parseRedeemResult(["propertyId": "p1"]), ["p1"])
        XCTAssertEqual(parseRedeemResult(nil), [])
        XCTAssertEqual(parseRedeemResult(["ok": true]), [])
        XCTAssertEqual(parseRedeemResult(["propertyIds": ["p1", 3] as [Any]]), ["p1"])
    }

    func testInviteGrantsPayloadSortsPermissionsAndKeepsEmptySets() {
        let payload = inviteGrantsPayload([
            InviteGrant(propertyId: "p1", permissions: [.site, .finance]),
            InviteGrant(propertyId: "p2", permissions: []),
        ])
        let grants = payload["grants"] as? [[String: Any]]
        XCTAssertEqual(grants?.count, 2)
        XCTAssertEqual(grants?[0]["propertyId"] as? String, "p1")
        XCTAssertEqual(grants?[0]["permissions"] as? [String], ["FINANCE", "SITE"])
        XCTAssertEqual(grants?[1]["permissions"] as? [String], [])
    }

    // MARK: Membri e trasferimenti

    func testParseMembersKeepsValidRolesAndIgnoresGarbage() {
        let data: [String: Any] = ["members": [
            ["uid": "u1", "role": "OWNER", "email": "a@example.com"],
            ["uid": "u2", "role": "COLLABORATOR", "email": ""],
            ["uid": "u3", "role": "ADMIN", "email": "x"],
            ["role": "OWNER"],
            "boh",
        ] as [Any]]
        XCTAssertEqual(parseMembers(data), [
            MemberInfo(uid: "u1", role: .owner, email: "a@example.com"),
            MemberInfo(uid: "u2", role: .collaborator, email: ""),
        ])
        XCTAssertTrue(parseMembers(nil).isEmpty)
    }

    func testParseMembersReadsPermissionsIgnoringUnknownOnes() {
        let data: [String: Any] = ["members": [
            ["uid": "u2", "role": "COLLABORATOR", "email": "", "permissions": ["FINANCE", "BOH", "SITE"]] as [String: Any],
            ["uid": "u3", "role": "COLLABORATOR", "email": "", "permissions": "FINANCE"],
            ["uid": "u4", "role": "COLLABORATOR", "email": ""],
        ] as [Any]]
        let parsed = parseMembers(data)
        XCTAssertEqual(parsed[0].permissions, [.finance, .site])
        XCTAssertTrue(parsed[1].permissions.isEmpty)
        XCTAssertTrue(parsed[2].permissions.isEmpty)
    }

    func testParseTransferResultDistinguishesCompletedFromPending() {
        XCTAssertEqual(parseTransferResult(["status": "completed", "newOwnerUid": "u9"]), TransferResult(completed: true, newOwnerUid: "u9"))
        XCTAssertEqual(parseTransferResult(["status": "pending"]), TransferResult(completed: false, newOwnerUid: nil))
        XCTAssertEqual(parseTransferResult(nil), TransferResult(completed: false, newOwnerUid: nil))
    }

    func testParseClaimed() {
        XCTAssertEqual(parseClaimed(["claimed": ["p1", "p2"]]), ["p1", "p2"])
        XCTAssertTrue(parseClaimed(["claimed": "boh"]).isEmpty)
        XCTAssertTrue(parseClaimed(nil).isEmpty)
    }

    // MARK: Alloggiati

    func testParseEsitoReadsValidCountAndPerRowDetails() {
        let esito = parseEsito([
            "schedineValide": 1,
            "dettaglio": [
                ["esito": true, "errorCod": "", "errorDes": "", "erroreDettaglio": ""] as [String: Any],
                ["esito": false, "errorCod": "12", "errorDes": "Documento non valido", "erroreDettaglio": "numero"],
            ] as [Any],
        ] as [String: Any])
        XCTAssertEqual(esito.schedineValide, 1)
        XCTAssertEqual(esito.dettaglio.count, 2)
        XCTAssertTrue(esito.dettaglio[0].esito)
        XCTAssertFalse(esito.dettaglio[1].esito)
        XCTAssertEqual(esito.dettaglio[1].errorDes, "Documento non valido")
    }

    func testParseEsitoOfGarbageIsEmpty() {
        let esito = parseEsito(nil)
        XCTAssertEqual(esito.schedineValide, 0)
        XCTAssertTrue(esito.dettaglio.isEmpty)
    }

    func testParseCsvAndReceipt() {
        XCTAssertEqual(parseCsvField(["csv": "a;b\n1;2"]), "a;b\n1;2")
        XCTAssertEqual(parseCsvField(nil), "")
        XCTAssertEqual(parseReceipt(["pdfBase64": "JVBERg=="]), Data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertNil(parseReceipt(["pdfBase64": ""]))
        XCTAssertNil(parseReceipt(nil))
    }

    func testDescribeHostErrorIsReadableInItalian() {
        XCTAssertEqual(describeHostError(code: "UNAVAILABLE", message: "x"), "Connessione assente o lenta: riprova")
        XCTAssertEqual(describeHostError(code: "PERMISSION_DENIED", message: "No access to this property"), "Non hai i permessi per questa operazione")
        XCTAssertEqual(describeHostError(code: "FAILED_PRECONDITION", message: "Invito già usato"), "Invito già usato")
        XCTAssertEqual(describeHostError(code: "NOT_FOUND", message: "Property not found"), "Casa non trovata")
        XCTAssertEqual(describeHostError(code: "NOT_FOUND", message: "Invito non valido"), "Invito non valido")
        XCTAssertEqual(describeHostError(code: "INVALID_ARGUMENT", message: nil), "Richiesta non valida")
        XCTAssertEqual(describeHostError(code: "INTERNAL", message: "boom"), "Errore del server (INTERNAL)")
    }

    func testDescribeSiteError() {
        XCTAssertEqual(describeSiteError(code: "PERMISSION_DENIED", message: nil), "Non gestisci questa casa")
        XCTAssertEqual(describeSiteError(code: "INVALID_ARGUMENT", message: "Zona mancante"), "Zona mancante")
        XCTAssertEqual(describeSiteError(code: "INVALID_ARGUMENT", message: nil), "Dati non validi")
        XCTAssertEqual(describeSiteError(code: "UNAVAILABLE", message: nil), "Connessione assente o lenta: riprova")
        XCTAssertEqual(describeSiteError(code: "INTERNAL", message: nil), "Errore del server (INTERNAL)")
    }

    // MARK: Annunci e host

    func testParseHostsReadsValidRowsAndSkipsBrokenOnes() {
        let data: [String: Any] = ["hosts": [
            ["uid": "u1", "email": "a@x.it", "displayName": "Anna", "propertyCount": 2, "pendingCount": 1,
             "propertyNames": ["Casa A", "Casa B"]] as [String: Any],
            ["email": "no-uid@x.it"],
            "junk",
        ] as [Any]]
        XCTAssertEqual(parseHosts(data), [
            HostRow(uid: "u1", email: "a@x.it", displayName: "Anna", propertyCount: 2, pendingCount: 1, propertyNames: ["Casa A", "Casa B"]),
        ])
        XCTAssertEqual(parseHosts(nil), [])
    }

    func testParseMissingFieldsReadsTheListFromAnIncompleteSubmitError() {
        XCTAssertEqual(parseMissing(["missing": ["Zona", "Almeno una foto"]]), ["Zona", "Almeno una foto"])
        XCTAssertEqual(parseMissing("x"), [])
    }

    // MARK: Prezzi

    func testParseSeasonalRatesWithIntAndDoublePrices() {
        let data: [String: Any] = ["rates": [
            ["startDate": "2026-08-01", "endDate": "2026-08-03", "pricePerNight": 100] as [String: Any],
            ["startDate": "2026-08-04", "endDate": "2026-08-06", "pricePerNight": 99.5],
        ] as [Any]]
        XCTAssertEqual(parseSeasonalRates(data), [
            SeasonalRateEntry(startDate: "2026-08-01", endDate: "2026-08-03", pricePerNight: 100),
            SeasonalRateEntry(startDate: "2026-08-04", endDate: "2026-08-06", pricePerNight: 99.5),
        ])
    }

    func testParseSeasonalRatesSkipsMalformedEntriesAndToleratesGarbage() {
        let data: [String: Any] = ["rates": [
            ["startDate": "2026-08-01", "endDate": "2026-08-03"] as [String: Any],
            "boh",
            ["startDate": "2026-08-07", "endDate": "2026-08-08", "pricePerNight": 80],
        ] as [Any]]
        XCTAssertEqual(parseSeasonalRates(data), [SeasonalRateEntry(startDate: "2026-08-07", endDate: "2026-08-08", pricePerNight: 80)])
        XCTAssertEqual(parseSeasonalRates(nil), [])
        XCTAssertEqual(parseSeasonalRates("x"), [])
    }

    func testParsePromotionsReadsValidEntriesAndSkipsMalformedOnes() {
        let data: [String: Any] = ["promotions": [
            ["id": "a", "startDate": "2026-08-01", "endDate": "2026-08-10", "discountType": "percentage", "discountValue": 20] as [String: Any],
            ["id": "b", "startDate": "2026-08-01"],
            "junk",
        ] as [Any]]
        XCTAssertEqual(parsePromotions(data), [
            PromoEntry(id: "a", startDate: "2026-08-01", endDate: "2026-08-10", discountType: "percentage", discountValue: 20),
        ])
        XCTAssertEqual(parsePromotions(nil), [])
    }

    func testParseSurchargesReadsTheMapAndSkipsBadKeys() {
        let data: [String: Any] = ["surcharges": ["3": 10, "4": 25.5, "x": 5, "5": "no"] as [String: Any]]
        XCTAssertEqual(parseSurcharges(data), [3: 10.0, 4: 25.5])
        XCTAssertEqual(parseSurcharges("bad"), [:])
    }
}
