# Inventario Android → iOS

**Spec di riferimento (baseline Android):** repo `Androidapp`, branch `main`, commit
`a43eb44eff144dc3c247a56f3e8e05c69132a02e` (2026-11-03; prima: `app-main-2026-09-28` `d162317`, e ancora prima `feat/fold-finanze-selezioni` `379b5c5`). Se l'Android cambia, aggiornare questa riga e rilanciare il controllo.
Controllo di completezza (da un clone con `../Androidapp` accanto): `python tools/gen_inventario.py --check` (aggiungi `--strict` nell'audit finale di F11).

Ogni file Kotlin dell'app Android (sorgenti e test) con la fase che lo porta. **Nessun file è fuori dal piano**: lo script di generazione fallisce se un file non ha fase. Aggiorna le colonne *iOS* e *Stato* man mano che porti; la fase F11 chiude solo se non resta nessuna riga con stato `—` (le uniche eccezioni ammesse sono `n/a` con motivo scritto qui).

Stati: `—` da fare · `scritto` scritto ma mai compilato · `compilato` · `provato` (simulatore/dispositivo) · `n/a` non serve su iOS (motivo in nota).

Totale (alla baseline): 249 file Kotlin (alle baseline precedenti 242 e 211).

## F1 — Livello dati completo

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `data/access/AccessScope.kt` | 86 | `Core/Access/AccessScope.swift` | scritto+test |
| `data/access/AccessSession.kt` | 39 | `Core/Access/AccessSession.swift` | scritto |
| `data/alloggiati/AlloggiatiModels.kt` | 15 | `Core/Models/SimpleModels.swift` | scritto |
| `data/alloggiati/LookupRepository.kt` | 54 | `Core/Services/LookupService.swift` | scritto |
| `data/model/AlloggiatiCredentials.kt` | 11 | `Core/Models/SimpleModels.swift` | scritto |
| `data/model/Contact.kt` | 10 | `Core/Models/SimpleModels.swift` | scritto |
| `data/model/Expense.kt` | 13 | `Core/Models/OtherModels.swift` | scritto |
| `data/model/GuestRecord.kt` | 22 | `Core/Models/OtherModels.swift` | scritto |
| `data/model/InventoryItem.kt` | 17 | `Core/Models/OtherModels.swift` | scritto |
| `data/model/InviteGrant.kt` | 4 | `Core/Models/SimpleModels.swift` | scritto |
| `data/model/ListingStatus.kt` | 20 | `Core/Models/ListingStatus.swift` | scritto |
| `data/model/PromoEntry.kt` | 15 | `Core/Models/SimpleModels.swift` | scritto |
| `data/model/Property.kt` | 76 | `Core/Models/Property.swift` | scritto |
| `data/model/PropertyPermission.kt` | 15 | `Core/Models/Property.swift` | scritto |
| `data/model/PropertyRole.kt` | 11 | `Core/Models/Property.swift` | scritto |
| `data/model/PropertySiteContent.kt` | 118 | `Core/Models/PropertySiteContent.swift` | scritto |
| `data/model/RecurringExpense.kt` | 16 | `Core/Models/OtherModels.swift` | scritto |
| `data/model/Reservation.kt` | 23 | `Core/Models/Reservation.swift` | scritto |
| `data/model/SeasonalRateEntry.kt` | 12 | `Core/Models/SimpleModels.swift` | scritto |
| `data/model/ServiceCatalog.kt` | 121 | `Core/Models/ServiceCatalog.swift` | scritto |
| `data/model/User.kt` | 10 | `Core/Models/OtherModels.swift` | scritto |
| `data/repository/AuthRepository.kt` | 52 | `Core/Services/AuthService.swift` | scritto (Google + uscita dall'account Google; email/registrazione non servono) |
| `data/repository/DatabaseRepository.kt` | 518 | `Core/Services/FirestoreService.swift` | scritto (completo) |
| `data/repository/FanOut.kt` | 14 | `Core/Services/FanOut.swift` | scritto |
| `data/repository/HostFunctionsRepository.kt` | 209 | `Core/Services/CloudFunctionsServices.swift, CallableParsers.swift, CloudErrors.swift` | scritto |
| `data/repository/ListingRepository.kt` | 63 | `Core/Services/CloudFunctionsServices.swift, CallableParsers.swift` | scritto |
| `data/repository/PriceRepository.kt` | 108 | `Core/Services/CloudFunctionsServices.swift, CallableParsers.swift` | scritto |
| `data/repository/SiteContentRepository.kt` | 64 | `Core/Services/SiteContentService.swift, CloudErrors.swift` | scritto |
| 🧪 `data/access/AccessScopeListingTest.kt` | 50 | `SiciliaHostTests/ModelsTests.swift` | scritto |
| 🧪 `data/access/AccessScopeTest.kt` | 146 | `SiciliaHostTests/AccessScopeTests.swift` | scritto |
| 🧪 `data/access/SuperAdminTest.kt` | 17 | `SiciliaHostTests/AccessScopeTests.swift` | scritto |
| 🧪 `data/model/ListingStatusTest.kt` | 20 | `SiciliaHostTests/ModelsTests.swift` | scritto |
| 🧪 `data/model/PropertyTest.kt` | 67 | `SiciliaHostTests/ModelsTests.swift` | scritto |
| 🧪 `data/model/ServiceCatalogTest.kt` | 49 | `SiciliaHostTests/ModelsTests.swift` | scritto |
| 🧪 `data/repository/FanOutTest.kt` | 36 | `SiciliaHostTests/ModelsTests.swift` | scritto |
| 🧪 `data/repository/HostFunctionsParsersTest.kt` | 223 | `SiciliaHostTests/CallableParsersTests.swift` | scritto |
| 🧪 `data/repository/ListingRepositoryParseTest.kt` | 30 | `SiciliaHostTests/CallableParsersTests.swift` | scritto |
| 🧪 `data/repository/ParseSeasonalRatesTest.kt` | 39 | `SiciliaHostTests/CallableParsersTests.swift` | scritto |
| 🧪 `data/repository/PriceRepositoryParseTest.kt` | 31 | `SiciliaHostTests/CallableParsersTests.swift` | scritto |
| `data/model/Messaging.kt` | 51 | `Core/Models/Messaging.swift` | compilato, test ok |
| `data/repository/MessagingRepository.kt` | 144 | `Core/Services/CloudFunctionsServices.swift (MessagingService), CallableParsers.swift, Core/Logic/MessagesFormat.swift (mergeMessages, isValidPhone)` | compilato, test ok |
| 🧪 `data/repository/MessagingRepositoryTest.kt` | 88 | `SiciliaHostTests/MessagingTests.swift` | compilato, test ok |

## F2 — Logica pura e utilità

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `data/invite/InviteLink.kt` | 29 | `Core/Logic/IdentityParsers.swift` | scritto |
| `data/mrz/MrzData.kt` | 14 | `Core/Logic/IdentityParsers.swift` | scritto |
| `data/mrz/MrzParser.kt` | 108 | `Core/Logic/IdentityParsers.swift` | scritto |
| `data/utils/AirbnbListingScraper.kt` | 80 | `Core/Logic/ListingImport.swift` | scritto |
| `data/utils/BookingExcelParser.kt` | 268 | `Core/Logic/BookingImport.swift, XlsReader.swift` | scritto (xls: lettore OLE2/BIFF8 scritto a mano, validato in Python sui file reali) |
| `data/utils/BookingImportPlan.kt` | 55 | `Core/Logic/BookingImport.swift` | scritto |
| `data/utils/BookingStats.kt` | 195 | `Core/Logic/BookingStats.swift` | scritto |
| `data/utils/DateRangeUtils.kt` | 6 | `Core/Logic/TimeUtils.swift` | scritto |
| `data/utils/ExpenseCategory.kt` | 46 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/FinanceInsights.kt` | 156 | `Core/Logic/FinanceInsights.swift` | scritto |
| `data/utils/FinancePeriod.kt` | 37 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/FinanceStats.kt` | 132 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/FinancialCalculator.kt` | 39 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/GeoMath.kt` | 81 | `Core/Logic/GeoMath.swift` | scritto |
| `data/utils/NominatimClient.kt` | 77 | `Core/Logic/ListingImport.swift` | scritto |
| `data/utils/OrphanExpenses.kt` | 12 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/OsmUserAgent.kt` | 12 | `Core/Logic/ListingImport.swift (osmUserAgent, UA iOS)` | scritto |
| `data/utils/PhotoEncoder.kt` | 73 | `Core/Logic/Photos.swift` | scritto (ImageIO; riceve Data, non Uri) |
| `data/utils/PhotoLogic.kt` | 41 | `Core/Logic/Photos.swift` | scritto |
| `data/utils/RecurringExpenses.kt` | 75 | `Core/Logic/Finance.swift` | scritto |
| `data/utils/ServiceImport.kt` | 84 | `Core/Logic/ServiceImport.swift` | scritto |
| 🧪 `data/invite/InviteLinkTest.kt` | 51 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/mrz/MrzParserTest.kt` | 112 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/AirbnbListingScraperTest.kt` | 46 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/BookingExcelParserTest.kt` | 221 | `SiciliaHostTests/BookingTests.swift, XlsReaderTests.swift` | scritto (xls con file sintetico + file reale opzionale) |
| 🧪 `data/utils/BookingImportPlanTest.kt` | 54 | `SiciliaHostTests/BookingTests.swift` | scritto |
| 🧪 `data/utils/BookingStatsTest.kt` | 141 | `SiciliaHostTests/BookingTests.swift, FinanceTests.swift` | scritto |
| 🧪 `data/utils/DateRangeUtilsTest.kt` | 31 | `SiciliaHostTests/FinanceTests.swift` | scritto |
| 🧪 `data/utils/FinanceStatsTest.kt` | 96 | `SiciliaHostTests/FinanceTests.swift` | scritto |
| 🧪 `data/utils/FinancialCalculatorTest.kt` | 94 | `SiciliaHostTests/FinanceTests.swift` | scritto |
| 🧪 `data/utils/GeoMathTest.kt` | 154 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/NominatimClientTest.kt` | 74 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/OrphanExpensesTest.kt` | 28 | `SiciliaHostTests/FinanceTests.swift` | scritto |
| 🧪 `data/utils/OsmUserAgentTest.kt` | 34 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/PhotoLogicTest.kt` | 58 | `SiciliaHostTests/LogicTests.swift` | scritto |
| 🧪 `data/utils/RecurringExpensesTest.kt` | 62 | `SiciliaHostTests/FinanceTests.swift` | scritto |
| 🧪 `data/utils/ServiceImportTest.kt` | 95 | `SiciliaHostTests/LogicTests.swift` | scritto |

## F3 — Accesso, shell, stile e navigazione

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `MainActivity.kt` | 66 | `App/SiciliaHostApp.swift, App/RootView.swift` | parziale→F10 (link d'invito e login Google fatti; permesso notifiche push in F10) |
| `Navigation.kt` | 195 | `Features/Navigation/Router.swift, Main/MainGateView.swift` | parziale→F9 (stack e destinazioni fatti; schermate di check-in/membri/wizard sono segnaposto) |
| `NavigationKeys.kt` | 20 | `Features/Navigation/Router.swift (Route, WizardLevel)` | scritto |
| `theme/Color.kt` | 69 | `Theme/Palette.swift (Brand, Theme)` | scritto |
| `theme/Dimens.kt` | 31 | `Theme/Palette.swift (Dimens)` | scritto |
| `theme/Theme.kt` | 122 | `Theme/Palette.swift (Theme, Radius; chiaro/scuro)` | scritto |
| `theme/Type.kt` | 111 | `Theme/Typography.swift` | scritto |
| `ui/adaptive/FieldRow.kt` | 40 | `` | n/a — solo iPhone: niente layout a due colonne |
| `ui/adaptive/FoldSplit.kt` | 125 | `` | n/a — solo iPhone: nessun layout per Fold/cerniera |
| `ui/adaptive/FoldSplitMath.kt` | 39 | `` | n/a — solo iPhone: nessun layout per Fold/cerniera |
| `ui/adaptive/FontScale.kt` | 18 | `UI/Style/CompactTopBar.swift (cappedFontScale)` | scritto |
| `ui/adaptive/HingeAwareBounds.kt` | 38 | `` | n/a — solo iPhone: nessuna cerniera; la fotocamera non ha posture |
| `ui/adaptive/LayoutMode.kt` | 24 | `` | n/a — solo iPhone: un solo layout (compatto) |
| `ui/adaptive/ListDetailPane.kt` | 61 | `` | n/a — solo iPhone: lista e dettaglio sono schermate impilate |
| `ui/common/CompactTopBar.kt` | 74 | `UI/Style/CompactTopBar.swift` | scritto |
| `ui/intro/IntroLogic.kt` | 10 | `Core/Logic/OnboardingLogic.swift` | scritto |
| `ui/intro/IntroOverlay.kt` | 90 | `Features/Intro/IntroOverlay.swift` | scritto |
| `ui/intro/IntroScreen.kt` | 252 | `Features/Intro/IntroScreen.swift` | scritto (senza lo spostamento del fondo con lo sfoglio) |
| `ui/intro/OnboardingController.kt` | 33 | `Core/State/OnboardingState.swift` | scritto |
| `ui/login/LoginScreen.kt` | 145 | `Features/Login/LoginView.swift` | scritto (solo Google, come l'Android; vedi DIARIO: accesso con Apple) |
| `ui/login/LoginViewModel.kt` | 46 | `Core/Services/AuthService.swift (signInWithGoogle)` | scritto |
| `ui/main/AccessState.kt` | 13 | `Features/Main/MainViewModel.swift` | scritto+test |
| `ui/main/LoadErrorScreen.kt` | 79 | `Features/Main/MainGateView.swift` | scritto |
| `ui/main/MainGate.kt` | 77 | `Features/Main/MainGateView.swift` | scritto |
| `ui/main/MainScreen.kt` | 427 | `Features/Main/MainTabView.swift, SiciliaNavBar.swift` | scritto (scheda Messaggi in `MainTabView`) |
| `ui/main/MainScreenViewModel.kt` | 135 | `Features/Main/MainViewModel.swift` | parziale (`refreshMessaging` è in `MainTabView`, senza badge: l'Android non lo mostra) |
| `ui/main/MainTabs.kt` | 30 | `Features/Main/MainTab.swift` | scritto (`MainTab.messaggi`, `messagingEnabled`) |
| `ui/main/OnboardingScreen.kt` | 212 | `Features/Main/OnboardingView.swift` | scritto |
| `ui/profile/ProfileScreen.kt` | 138 | `Features/Profile/ProfileView.swift` | compilato (n/a: riga diagnostica del Fold e widget Cactus; canali notifiche → impostazioni di sistema) |
| `ui/style/AmbientBackground.kt` | 81 | `UI/Style/AmbientBackground.swift` | scritto |
| `ui/style/Buttons.kt` | 183 | `UI/Style/Buttons.swift` | scritto |
| `ui/style/Glass.kt` | 109 | `UI/Style/Glass.swift` | scritto |
| `ui/style/Motion.kt` | 30 | `Theme/Motion.swift (reduce motion = Environment accessibilityReduceMotion)` | scritto |
| `ui/style/SelectField.kt` | 106 | `UI/Style/Surfaces.swift (SelectField)` | scritto |
| `ui/style/Surfaces.kt` | 147 | `UI/Style/Surfaces.swift (appCard, SectionLabel)` | scritto (i dialog sono gli alert/sheet di sistema) |
| `ui/terms/HostTerms.kt` | 67 | `Features/Terms/HostTerms.swift` | scritto |
| `ui/terms/HostTermsDialog.kt` | 72 | `Features/Terms/HostTerms.swift (HostTermsSheet)` | scritto |
| `ui/tour/TourLogic.kt` | 52 | `Core/Logic/OnboardingLogic.swift` | scritto |
| `ui/tour/TourOverlay.kt` | 183 | `Features/Tour/TourOverlay.swift` | scritto |
| `ui/tour/TourState.kt` | 51 | `Core/State/OnboardingState.swift, Features/Tour/TourOverlay.swift (tourTarget)` | scritto |
| 🧪 `ui/adaptive/FoldSplitTest.kt` | 64 | `` | n/a — solo iPhone |
| 🧪 `ui/adaptive/LayoutModeTest.kt` | 32 | `` | n/a — solo iPhone |
| 🧪 `ui/intro/IntroLogicTest.kt` | 30 | `SiciliaHostTests/OnboardingTests.swift` | scritto |
| 🧪 `ui/main/AccessStateTest.kt` | 48 | `SiciliaHostTests/AccessScopeTests.swift` | scritto |
| 🧪 `ui/main/MainTabsTest.kt` | 90 | `SiciliaHostTests/AccessScopeTests.swift` | scritto (caso Messaggi in `MessagingTests`) |
| 🧪 `ui/tour/TourLogicTest.kt` | 39 | `SiciliaHostTests/OnboardingTests.swift` | scritto |
| `ui/profile/PrivacyContent.kt` | 52 | `Core/Logic/ProfileLogic.swift` | compilato, test ok |
| `ui/profile/ProfileViewModel.kt` | 59 | `Features/Profile/ProfileModels.swift` | compilato, test ok |
| `ui/profile/HouseAccessLogic.kt` | 45 | `Core/Logic/ProfileLogic.swift` | compilato, test ok |
| `ui/profile/HouseAccessScreen.kt` | 140 | `Features/Profile/HouseAccessView.swift` | compilato, test ok |
| `ui/profile/PrivacySecurityScreen.kt` | 93 | `Features/Profile/PrivacyView.swift` | compilato, test ok |
| `ui/profile/DisplayName.kt` | 19 | `Core/Logic/ProfileLogic.swift` | compilato, test ok |
| `ui/profile/LegalLinks.kt` | 7 | `Core/Logic/ProfileLogic.swift` | compilato, test ok |
| `ui/profile/HouseAccessViewModel.kt` | 145 | `Features/Profile/ProfileModels.swift` | compilato, test ok |
| 🧪 `ui/profile/DisplayNameTest.kt` | 30 | `SiciliaHostTests/ProfileTests.swift` | compilato, test ok |
| 🧪 `ui/profile/PrivacyContentTest.kt` | 37 | `SiciliaHostTests/ProfileTests.swift` | compilato, test ok |
| 🧪 `ui/profile/HouseAccessLogicTest.kt` | 78 | `SiciliaHostTests/ProfileTests.swift` | compilato, test ok |

## F4 — Home

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/dashboard/DashboardScreen.kt` | 412 | `Features/Home/HomeView.swift`, `Core/Logic/AgendaLogic.swift` | compilato+test |

## F5 — Agenda, prenotazioni e prezzi

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/calendar/CalendarScreen.kt` | 391 | `Features/Agenda/AgendaView.swift`, `Core/Logic/AgendaLogic.swift` | compilato+test |
| `ui/calendar/GuestPricing.kt` | 69 | `Core/Logic/PriceLogic.swift` | compilato+test |
| `ui/calendar/PriceEditorScreen.kt` | 470 | `Features/Agenda/PriceEditorView.swift` | compilato |
| `ui/calendar/PriceEditorViewModel.kt` | 351 | `Features/Agenda/PriceEditorModel.swift` | compilato |
| `ui/calendar/PriceSelection.kt` | 105 | `Core/Logic/PriceLogic.swift` | compilato+test |
| `ui/reservation/ReservationEditScreen.kt` | 312 | `Features/Reservation/ReservationEditView.swift`, `Core/Logic/AgendaLogic.swift` | compilato+test |
| 🧪 `ui/calendar/CalendarGridTest.kt` | 35 | `SiciliaHostTests/AgendaTests.swift` | compilato, verde |
| 🧪 `ui/calendar/GuestPricingTest.kt` | 85 | `SiciliaHostTests/AgendaTests.swift` | compilato, verde |
| 🧪 `ui/calendar/PriceSelectionTest.kt` | 126 | `SiciliaHostTests/AgendaTests.swift` | compilato, verde |

## F6 — Scorte

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/inventory/InventoryItemDetailDialog.kt` | 224 | `Features/Inventory/InventorySheets.swift` (`InventoryDetailSheet`) | compilato |
| `ui/inventory/InventoryScreen.kt` | 1503 | `Features/Inventory/InventoryView.swift`, `InventoryModel.swift`, `InventorySheets.swift`, `Core/Logic/InventoryLogic.swift` | compilato+test |
| `ui/inventory/StockStatus.kt` | 16 | `Core/Logic/InventoryLogic.swift` | compilato+test |
| 🧪 `ui/inventory/NormalizeBarcodeTest.kt` | 35 | `SiciliaHostTests/InventoryTests.swift` | compilato, verde |
| 🧪 `ui/inventory/StockStatusTest.kt` | 44 | `SiciliaHostTests/InventoryTests.swift` | compilato, verde |

## F7 — Finanze

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/finance/FinanceCharts.kt` | 216 | `Features/Finance/FinanceParts.swift` (grafici) | compilato |
| `ui/finance/FinanceDetailScreens.kt` | 255 | `Features/Finance/FinanceDetailViews.swift`, `Core/Logic/FinanceViewLogic.swift` (`statsKpis`) | compilato+test |
| `ui/finance/FinanceListKeys.kt` | 21 | `Core/Logic/FinanceViewLogic.swift` | compilato+test |
| `ui/finance/FinanceParts.kt` | 195 | `Features/Finance/FinanceParts.swift`, `Core/Logic/FinanceViewLogic.swift` (formati) | compilato+test |
| `ui/finance/FinanceScreen.kt` | 896 | `Features/Finance/FinanceView.swift`, `FinanceModel.swift` | compilato+test |
| `ui/finance/FinanceView.kt` | 69 | `Core/Logic/FinanceViewLogic.swift` | compilato+test |
| 🧪 `ui/finance/FinanceListKeysTest.kt` | 47 | `SiciliaHostTests/FinanceViewTests.swift` | compilato, verde |

## F8 — Check-in Alloggiati

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/checkin/CheckinScreen.kt` | 208 | `Features/Checkin/CheckinView.swift` | compilato |
| `ui/checkin/CheckinSendScreen.kt` | 216 | `Features/Checkin/CheckinView.swift` (`CheckinSendView`) | compilato+test |
| `ui/checkin/CheckinViewModel.kt` | 158 | `Features/Checkin/CheckinModel.swift`, `Core/Logic/CheckinLogic.swift` | compilato+test |
| `ui/checkin/GuestFormScreen.kt` | 359 | `Features/Checkin/GuestFormView.swift`, `Core/Logic/CheckinLogic.swift` | compilato+test |
| `ui/checkin/MrzScannerScreen.kt` | 280 | `Features/Checkin/MrzScannerView.swift` | compilato |

## F9 — Case, sito, posizione, membri e inviti

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/cases/AppFieldsDraft.kt` | 128 | `Core/Logic/SiteDraftLogic.swift` | compilato+test |
| `ui/cases/CaseDetailScreen.kt` | 342 | `Features/Cases/CaseDetailView.swift` | compilato |
| `ui/cases/CaseLogic.kt` | 93 | `Core/Logic/CaseLogic.swift` | compilato+test |
| `ui/cases/CaseSaveLogic.kt` | 26 | `Core/Logic/CaseLogic.swift` | compilato+test |
| `ui/cases/CaseSections.kt` | 590 | `Features/Cases/CaseSections.swift` | compilato |
| `ui/cases/CasesScreen.kt` | 359 | `Features/Cases/CasesView.swift` | compilato |
| `ui/cases/CasesViewModel.kt` | 259 | `Features/Cases/CasesModel.swift` | compilato |
| `ui/cases/HostsScreen.kt` | 142 | `Features/Cases/CasesView.swift` (`HostsView`) | compilato |
| `ui/cases/ListingStatusUi.kt` | 41 | `Features/Cases/CasesView.swift` (`ListingStatusPill`) | compilato |
| `ui/cases/PublishOnSiteCard.kt` | 31 | `Features/Cases/CaseDetailView.swift` | compilato |
| `ui/cases/SiteTrack.kt` | 24 | `Core/Models/ListingStatus.swift` | compilato+test |
| `ui/invite/InviteFormat.kt` | 13 | `Core/Logic/MembersLogic.swift` (`InviteText`) | compilato+test |
| `ui/invite/InviteScreen.kt` | 135 | `Features/Invite/InviteView.swift` | compilato |
| `ui/invite/InviteViewModel.kt` | 79 | `Features/Invite/InviteView.swift` (`InviteModel`), protocollo `InviteAPI` | compilato+test |
| `ui/invite/PendingInvite.kt` | 33 | `Core/State/OnboardingState.swift` | scritto |
| `ui/members/InviteComposerDialog.kt` | 115 | `Features/Members/MembersView.swift` (`InviteComposerSheet`) | compilato |
| `ui/members/InviteForm.kt` | 64 | `Core/Logic/MembersLogic.swift` | compilato+test |
| `ui/members/MembersLogic.kt` | 38 | `Core/Logic/MembersLogic.swift` | compilato+test |
| `ui/members/MembersScreen.kt` | 279 | `Features/Members/MembersView.swift` | compilato |
| `ui/members/MembersViewModel.kt` | 205 | `Features/Members/MembersView.swift` (`MembersModel`) | compilato |
| `ui/property/CredentialsLogic.kt` | 12 | `Core/Logic/CaseLogic.swift` (`CaseSaveLogic.credentialsToSave`) | compilato+test |
| `ui/property/PropertyManagementViewModel.kt` | 321 | `Features/Cases/CasesModel.swift` (credenziali, import Excel); sync iCal → F10 | parziale→F10 |
| `ui/site/SiteContentViewModel.kt` | 174 | `Features/Cases/CasesModel.swift` (`SiteContentModel`) | compilato |
| `ui/site/SiteDraft.kt` | 265 | `Core/Logic/SiteDraftLogic.swift` | compilato+test |
| `ui/site/SiteDraftSaver.kt` | 85 | n/a: bozze `Codable` in `@State` (niente Bundle Android) | n/a |
| `ui/site/SiteFormParts.kt` | 66 | `Features/Cases/CaseSections.swift` (`SiteTextField`, `SubsectionTitle`) | compilato |
| `ui/site/SitePhotosSection.kt` | 116 | `Features/Cases/CaseSections.swift` | compilato |
| `ui/site/SiteTranslationsSection.kt` | 103 | `Features/Cases/CaseSections.swift` | compilato |
| `ui/site/content/PageContentDraft.kt` | 373 | `Core/Logic/PageContentDraftLogic.swift` | compilato+test |
| `ui/site/content/PageContentEditor.kt` | 262 | `Features/Cases/ContentEditors.swift` | compilato |
| `ui/site/content/ServicesDraft.kt` | 170 | `Core/Logic/ServicesDraftLogic.swift` | compilato+test |
| `ui/site/content/ServicesEditor.kt` | 332 | `Features/Cases/ContentEditors.swift` | compilato |
| `ui/site/position/MapMarkerIcons.kt` | 37 | `Features/Cases/PositionViews.swift` (simboli SF) | compilato |
| `ui/site/position/PositionMap.kt` | 266 | `Features/Cases/PositionViews.swift` (MapKit) | compilato |
| `ui/site/position/PositionPickerDialog.kt` | 382 | `Features/Cases/PositionViews.swift` | compilato |
| `ui/site/position/PositionSection.kt` | 130 | `Features/Cases/PositionViews.swift` | compilato |
| `ui/site/position/PositionState.kt` | 94 | `Core/Logic/SiteDraftLogic.swift` | compilato+test |
| `ui/wizard/AppLevelSteps.kt` | 113 | `Features/Wizard/NewCaseWizardView.swift` | compilato |
| `ui/wizard/NewCaseWizardScreen.kt` | 489 | `Features/Wizard/NewCaseWizardView.swift` | compilato |
| `ui/wizard/WizardLogic.kt` | 68 | `Core/Logic/CaseLogic.swift` | compilato+test |
| 🧪 `ui/cases/AppFieldsDraftTest.kt` | 62 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/cases/CaseLogicTest.kt` | 91 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/cases/CaseSaveLogicTest.kt` | 37 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/cases/SiteTrackTest.kt` | 41 | `SiciliaHostTests/CaseLogicTests.swift` (`SiteTrackTests`) | compilato, verde |
| 🧪 `ui/invite/InviteFormatTest.kt` | 33 | `SiciliaHostTests/MembersTests.swift` | compilato, verde |
| 🧪 `ui/invite/InviteViewModelTest.kt` | 134 | `SiciliaHostTests/MembersTests.swift` | compilato, verde |
| 🧪 `ui/invite/PendingInviteTest.kt` | 24 | `SiciliaHostTests/OnboardingTests.swift` | scritto |
| 🧪 `ui/members/InviteFormTest.kt` | 104 | `SiciliaHostTests/MembersTests.swift` | compilato, verde |
| 🧪 `ui/members/MembersLogicTest.kt` | 71 | `SiciliaHostTests/MembersTests.swift` | compilato, verde |
| 🧪 `ui/property/CredentialsLogicTest.kt` | 33 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/property/PropertyManagementViewModelTest.kt` | 28 | `SiciliaHostTests/CaseLogicTests.swift` (`SiteTrackTests`) | compilato, verde |
| 🧪 `ui/site/SiteDraftSaverTest.kt` | 46 | `SiciliaHostTests/CaseLogicTests.swift` (andata e ritorno `Codable`) | compilato, verde |
| 🧪 `ui/site/SiteDraftTest.kt` | 389 | `SiciliaHostTests/SiteDraftTests.swift` | compilato, verde |
| 🧪 `ui/site/content/PageContentDraftTest.kt` | 324 | `SiciliaHostTests/PageContentTests.swift` (casi principali) | compilato, verde |
| 🧪 `ui/site/content/ServicesDraftTest.kt` | 204 | `SiciliaHostTests/PageContentTests.swift` (casi principali) | compilato, verde |
| 🧪 `ui/site/position/PositionStateTest.kt` | 200 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/wizard/WizardLogicTest.kt` | 79 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| `ui/cases/DeleteCase.kt` | 103 | `Core/Logic/CaseLogic.swift` (logica) + `Features/Cases/CaseDetailView.swift` (`DeleteCaseSheet`) | compilato |
| `ui/wizard/importing/ImportStep.kt` | 258 | `Features/Wizard/NewCaseWizardView.swift` (`ImportStepView`, `ReviewBanner`, `ImportedPhotosView`) | compilato |
| `ui/wizard/importing/ImportApply.kt` | 110 | `Core/Logic/ListingImportFlow.swift` | compilato+test |
| `ui/wizard/importing/ImportViewModel.kt` | 175 | `Features/Wizard/ImportModel.swift` | compilato |
| `ui/wizard/importing/OwnershipDeclaration.kt` | 9 | `Core/Logic/ListingImportFlow.swift` | compilato+test |
| `ui/wizard/importing/ImportRepository.kt` | 75 | `Features/Wizard/ImportModel.swift` (`ImportService`) + `Core/Logic/ListingImportFlow.swift` (errori, `PhotoProgress`) | compilato+test |
| `ui/wizard/importing/ListingImport.kt` | 105 | `Core/Logic/ListingImportFlow.swift` | compilato+test |
| `ui/wizard/importing/ImportUrls.kt` | 41 | `Core/Logic/ListingImportFlow.swift` | compilato+test |
| `ui/wizard/importing/ImportReview.kt` | 52 | `Core/Logic/ListingImportFlow.swift` | compilato+test |
| `ui/wizard/importing/ListingFetcher.kt` | 186 | `Features/Wizard/ImportModel.swift` (download: URLSession, WKWebView) + `Core/Logic/ListingImportFlow.swift` (parte pura) | compilato+test |
| 🧪 `ui/cases/DeleteCaseTest.kt` | 43 | `SiciliaHostTests/CaseLogicTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ListingFetcherTest.kt` | 91 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ImportReviewTest.kt` | 30 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ImportUrlsTest.kt` | 39 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ImportApplyTest.kt` | 143 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/PhotoProgressTest.kt` | 45 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/OwnershipDeclarationTest.kt` | 20 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ListingImportTest.kt` | 107 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |
| 🧪 `ui/wizard/importing/ImportRepositoryTest.kt` | 28 | `SiciliaHostTests/ListingImportTests.swift` | compilato, verde |

## F10 — Sfondo, notifiche e sincronizzazioni

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `services/LocalNotifier.kt` | 45 | `Core/Services/Notifications.swift (LocalNotifier)` | compilato, test ok |
| `services/MyFirebaseMessagingService.kt` | 38 | `App/AppDelegate.swift, Core/Services/Notifications.swift (PushToken)` | compilato, test ok |
| `sync/BookingExcelReminderWorker.kt` | 49 | `Core/Logic/ExcelReminder.swift, Core/Services/Notifications.swift (ExcelReminderScheduler)` | compilato (notifica locale pianificata, non un lavoro periodico) |
| `sync/ICalSyncWorker.kt` | 251 | `Core/Logic/ICalSync.swift (parte pura: parseEvents, buildSyncPlan, safeErrorReason)` | compilato (`Core/Services/ICalSyncService.swift`, giro in `AutoSync`; echi Booking portati) |
| 🧪 `sync/ICalSyncWorkerTest.kt` | 171 | `SiciliaHostTests/LogicTests.swift, BackgroundSyncTests.swift (echi)` | compilato, test ok |
| `services/NotificationChannels.kt` | 29 | n/a | iOS non ha canali di notifica: si regola tutto dalle impostazioni di sistema (Profilo → Notifiche) |

## F12 — Messaggi degli ospiti

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/messages/MessagesScreen.kt` | 391 | `Features/Messages/MessagesView.swift` | compilato, test ok |
| `ui/messages/MessagesViewModel.kt` | 204 | `Features/Messages/MessagesModel.swift` | compilato, test ok |
| `ui/messages/MessagesFormat.kt` | 81 | `Core/Logic/MessagesFormat.swift` | compilato, test ok |
| 🧪 `ui/messages/MessagesFormatTest.kt` | 35 | `SiciliaHostTests/MessagingTests.swift` | compilato, test ok |

## F13 — Assistente Cactus

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `data/repository/AssistantRepository.kt` | 267 | `Core/Services/AssistantService.swift` | scritto |
| `ui/assistant/AssistantApi.kt` | 27 | `Core/Services/AssistantService.swift (AssistantAPI)` | scritto |
| `ui/assistant/AssistantModels.kt` | 198 | `Core/Models/AssistantModels.swift` | scritto |
| `ui/assistant/AssistantWidgets.kt` | 41 | `Core/Models/AssistantWidgets.swift` | scritto |
| `ui/assistant/AssistantWidgetLogic.kt` | 123 | `Core/Logic/AssistantWidgetLogic.swift` | scritto |
| `ui/assistant/AssistantTexts.kt` | 171 | `Core/Logic/AssistantTexts.swift` | scritto |
| `ui/assistant/AssistantVoice.kt` | 184 | `Features/Assistant/AssistantVoice.swift` | scritto |
| `ui/assistant/AssistantViewModel.kt` | 841 | `Features/Assistant/AssistantModel.swift` | scritto |
| `ui/assistant/AssistantOverlay.kt` | 371 | `Features/Assistant/AssistantOverlay.swift` | scritto |
| `ui/assistant/AssistantSheet.kt` | 546 | `Features/Assistant/CactusOverlayView.swift` | scritto |
| `ui/assistant/CactusOverlayScreen.kt` | 1377 | `Features/Assistant/CactusOverlayView.swift` | scritto |
| `ui/assistant/cactus/CactusAvatarEngine.kt` | 553 | `Features/Assistant/CactusAvatarEngine.swift` | scritto |
| `ui/assistant/cactus/CactusAvatarGate.kt` | 136 | `Features/Assistant/CactusAvatarGate.swift` | scritto |
| `ui/assistant/cactus/CactusAvatarView.kt` | 80 | `Features/Assistant/CactusAvatarView.swift` | scritto |
| `ui/assistant/cactus/CactusLiveLogic.kt` | 207 | `Core/Logic/CactusLiveLogic.swift` | scritto |
| `ui/assistant/cactus/CactusNeon.kt` | 93 | `Features/Assistant/CactusOverlayView.swift` | scritto |
| `ui/assistant/cactus/CactusNodes.kt` | 62 | `Features/Assistant/CactusNodes.swift` | scritto |
| `ui/assistant/cactus/CactusOverlayLogic.kt` | 112 | `Core/Logic/CactusOverlayLogic.swift` | scritto |
| `ui/assistant/cactus/CactusPose.kt` | 169 | `Core/Logic/CactusPose.swift` | scritto |
| `ui/assistant/cactus/ReducedMotion.kt` | 36 | `Features/Assistant/ReducedMotion.swift` | scritto |
| `ui/assistant/home/CactusAppWidgetProvider.kt` | 106 | n/a (iOS WidgetKit estensione a parte) | n/a |
| `ui/assistant/home/CactusHomeWidgetLogic.kt` | 127 | n/a (iOS WidgetKit estensione a parte) | n/a |
| `ui/assistant/home/CactusQuickActivity.kt` | 249 | n/a (iOS WidgetKit estensione a parte) | n/a |
| `ui/assistant/widgets/AmountWidgetView.kt` | 98 | `Features/Assistant/WidgetViews.swift` | scritto |
| `ui/assistant/widgets/ChoiceWidgetView.kt` | 79 | `Features/Assistant/WidgetViews.swift` | scritto |
| `ui/assistant/widgets/DatesWidgetView.kt` | 160 | `Features/Assistant/WidgetViews.swift` | scritto |
| `ui/assistant/widgets/ProposalGroup.kt` | 340 | `Features/Assistant/ProposalViews.swift` | scritto |
| `ui/assistant/widgets/SimpleWidgetViews.kt` | 61 | `Features/Assistant/WidgetViews.swift` | scritto |
| `ui/assistant/widgets/WidgetCommon.kt` | 59 | `Features/Assistant/WidgetViews.swift` | scritto |
| `ui/assistant/widgets/WidgetView.kt` | 30 | `Features/Assistant/WidgetViews.swift` | scritto |
| 🧪 `data/repository/AssistantRepositoryTest.kt` | 125 | `SiciliaHostTests/AssistantTests.swift` | scritto |
| 🧪 `data/repository/AssistantWidgetParsingTest.kt` | 117 | `SiciliaHostTests/AssistantWidgetTests.swift` | scritto |
| 🧪 `ui/assistant/AssistantModelsTest.kt` | 92 | `SiciliaHostTests/AssistantTests.swift` | scritto |
| 🧪 `ui/assistant/AssistantOverlayTest.kt` | 56 | `SiciliaHostTests/AssistantModelTests.swift` | scritto |
| 🧪 `ui/assistant/AssistantViewModelTest.kt` | 1159 | `SiciliaHostTests/AssistantModelTests.swift` | scritto |
| 🧪 `ui/assistant/AssistantWidgetLogicTest.kt` | 147 | `SiciliaHostTests/AssistantWidgetTests.swift` | scritto |
| 🧪 `ui/assistant/cactus/CactusAvatarAssetTest.kt` | 172 | `SiciliaHostTests/CactusAvatarTests.swift` | scritto |
| 🧪 `ui/assistant/cactus/CactusAvatarGateTest.kt` | 134 | `SiciliaHostTests/CactusAvatarTests.swift` | scritto |
| 🧪 `ui/assistant/cactus/CactusLiveLogicTest.kt` | 136 | `SiciliaHostTests/CactusLiveTests.swift` | scritto |
| 🧪 `ui/assistant/cactus/CactusOverlayLogicTest.kt` | 151 | `SiciliaHostTests/CactusOverlayLogicTests.swift` | scritto |
| 🧪 `ui/assistant/cactus/CactusPoseTest.kt` | 217 | `SiciliaHostTests/CactusPoseTests.swift` | scritto |
| 🧪 `ui/assistant/home/CactusHomeWidgetLogicTest.kt` | 119 | n/a (iOS WidgetKit estensione a parte) | n/a |

## Risorse e manifest

| Fase | Voce | Cosa | Stato |
|---|---|---|---|
| F11 | `drawable/logo_transparent.png, ic_launcher_*, mipmap-*` | Icona app (AppIcon) e logo | — |
| F11 | `drawable/ic_map_pin.xml, ic_map_eye.xml, ic_map_area_handle_bg.xml` | Marcatori mappa (usati da F9) | — |
| F11 | `values/strings.xml, themes.xml` | Testi e tema: Localizable / asset catalog | — |
| F11 | `xml/file_provider_paths.xml` | Condivisione file (ricevuta Alloggiati, ecc.): ShareLink / UIActivityViewController | — |
| F11 | `xml/backup_rules.xml, data_extraction_rules.xml` | Niente da portare (backup iOS gestito dal sistema) | n/a |
| F10 | `POST_NOTIFICATIONS, FirebaseMessagingService` | Notifiche push (APNs + FCM) | — |
| F8 | `CAMERA` | NSCameraUsageDescription (già in project.yml) | scritto |
