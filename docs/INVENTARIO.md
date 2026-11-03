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
| `data/model/Messaging.kt` | 51 |  | — |
| `data/repository/MessagingRepository.kt` | 144 |  | — |
| 🧪 `data/repository/MessagingRepositoryTest.kt` | 88 |  | — |

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
| `ui/main/MainScreen.kt` | 427 | `Features/Main/MainTabView.swift, SiciliaNavBar.swift` | parziale→F12 (scheda Messaggi del 2026-11-03 da aggiungere) |
| `ui/main/MainScreenViewModel.kt` | 135 | `Features/Main/MainViewModel.swift` | parziale→F12 (`refreshMessaging`) |
| `ui/main/MainTabs.kt` | 30 | `Features/Main/MainTab.swift` | parziale→F12 (`MainTab.Messaggi`, `messagingEnabled`) |
| `ui/main/OnboardingScreen.kt` | 212 | `Features/Main/OnboardingView.swift` | scritto |
| `ui/profile/ProfileScreen.kt` | 138 | `Features/Profile/ProfileView.swift` | scritto (senza la riga diagnostica del Fold) |
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
| 🧪 `ui/main/MainTabsTest.kt` | 90 | `SiciliaHostTests/AccessScopeTests.swift` | parziale→F12 (casi Messaggi) |
| 🧪 `ui/tour/TourLogicTest.kt` | 39 | `SiciliaHostTests/OnboardingTests.swift` | scritto |
| `ui/profile/PrivacyContent.kt` | 52 |  | — |
| `ui/profile/ProfileViewModel.kt` | 59 |  | — |
| `ui/profile/HouseAccessLogic.kt` | 45 |  | — |
| `ui/profile/HouseAccessScreen.kt` | 140 |  | — |
| `ui/profile/PrivacySecurityScreen.kt` | 93 |  | — |
| `ui/profile/DisplayName.kt` | 19 |  | — |
| `ui/profile/LegalLinks.kt` | 7 |  | — |
| `ui/profile/HouseAccessViewModel.kt` | 145 |  | — |
| 🧪 `ui/profile/DisplayNameTest.kt` | 30 |  | — |
| 🧪 `ui/profile/PrivacyContentTest.kt` | 37 |  | — |
| 🧪 `ui/profile/HouseAccessLogicTest.kt` | 78 |  | — |

## F4 — Home

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/dashboard/DashboardScreen.kt` | 412 | `Features/Home/HomeView.swift`, `Core/Logic/AgendaLogic.swift` | scritto+test |

## F5 — Agenda, prenotazioni e prezzi

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/calendar/CalendarScreen.kt` | 391 | `Features/Agenda/AgendaView.swift`, `Core/Logic/AgendaLogic.swift` | scritto+test |
| `ui/calendar/GuestPricing.kt` | 69 | `Core/Logic/PriceLogic.swift` | scritto+test |
| `ui/calendar/PriceEditorScreen.kt` | 470 | `Features/Agenda/PriceEditorView.swift` | scritto |
| `ui/calendar/PriceEditorViewModel.kt` | 351 | `Features/Agenda/PriceEditorModel.swift` | scritto |
| `ui/calendar/PriceSelection.kt` | 105 | `Core/Logic/PriceLogic.swift` | scritto+test |
| `ui/reservation/ReservationEditScreen.kt` | 312 | `Features/Reservation/ReservationEditView.swift`, `Core/Logic/AgendaLogic.swift` | scritto+test |
| 🧪 `ui/calendar/CalendarGridTest.kt` | 35 | `SiciliaHostTests/AgendaTests.swift` | scritto |
| 🧪 `ui/calendar/GuestPricingTest.kt` | 85 | `SiciliaHostTests/AgendaTests.swift` | scritto |
| 🧪 `ui/calendar/PriceSelectionTest.kt` | 126 | `SiciliaHostTests/AgendaTests.swift` | scritto |

## F6 — Scorte

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/inventory/InventoryItemDetailDialog.kt` | 224 |  | — |
| `ui/inventory/InventoryScreen.kt` | 1503 |  | — |
| `ui/inventory/StockStatus.kt` | 16 |  | — |
| 🧪 `ui/inventory/NormalizeBarcodeTest.kt` | 35 |  | — |
| 🧪 `ui/inventory/StockStatusTest.kt` | 44 |  | — |

## F7 — Finanze

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/finance/FinanceCharts.kt` | 216 |  | — |
| `ui/finance/FinanceDetailScreens.kt` | 255 |  | — |
| `ui/finance/FinanceListKeys.kt` | 21 |  | — |
| `ui/finance/FinanceParts.kt` | 195 |  | — |
| `ui/finance/FinanceScreen.kt` | 896 |  | — |
| `ui/finance/FinanceView.kt` | 69 |  | — |
| 🧪 `ui/finance/FinanceListKeysTest.kt` | 47 |  | — |

## F8 — Check-in Alloggiati

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/checkin/CheckinScreen.kt` | 208 |  | — |
| `ui/checkin/CheckinSendScreen.kt` | 216 |  | — |
| `ui/checkin/CheckinViewModel.kt` | 158 |  | — |
| `ui/checkin/GuestFormScreen.kt` | 359 |  | — |
| `ui/checkin/MrzScannerScreen.kt` | 280 |  | — |

## F9 — Case, sito, posizione, membri e inviti

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/cases/AppFieldsDraft.kt` | 128 |  | — |
| `ui/cases/CaseDetailScreen.kt` | 342 |  | — |
| `ui/cases/CaseLogic.kt` | 93 | `Core/Models/SimpleModels.swift (solo HostRow)` | parziale→F9 |
| `ui/cases/CaseSaveLogic.kt` | 26 |  | — |
| `ui/cases/CaseSections.kt` | 590 |  | — |
| `ui/cases/CasesScreen.kt` | 359 |  | — |
| `ui/cases/CasesViewModel.kt` | 259 |  | — |
| `ui/cases/HostsScreen.kt` | 142 |  | — |
| `ui/cases/ListingStatusUi.kt` | 41 |  | — |
| `ui/cases/PublishOnSiteCard.kt` | 31 |  | — |
| `ui/cases/SiteTrack.kt` | 24 | `Core/Models/ListingStatus.swift (isOnSiteTrack, canEditCalendarPrices, approvedIds)` | parziale→F9 |
| `ui/invite/InviteFormat.kt` | 13 |  | — |
| `ui/invite/InviteScreen.kt` | 135 |  | — |
| `ui/invite/InviteViewModel.kt` | 79 | `Core/Services/CloudFunctionsServices.swift (solo protocollo InviteAPI)` | parziale→F9 |
| `ui/invite/PendingInvite.kt` | 33 | `Core/State/OnboardingState.swift` | scritto |
| `ui/members/InviteComposerDialog.kt` | 115 |  | — |
| `ui/members/InviteForm.kt` | 64 |  | — |
| `ui/members/MembersLogic.kt` | 38 |  | — |
| `ui/members/MembersScreen.kt` | 279 |  | — |
| `ui/members/MembersViewModel.kt` | 205 |  | — |
| `ui/property/CredentialsLogic.kt` | 12 |  | — |
| `ui/property/PropertyManagementViewModel.kt` | 321 |  | — |
| `ui/site/SiteContentViewModel.kt` | 174 |  | — |
| `ui/site/SiteDraft.kt` | 265 |  | — |
| `ui/site/SiteDraftSaver.kt` | 85 |  | — |
| `ui/site/SiteFormParts.kt` | 66 |  | — |
| `ui/site/SitePhotosSection.kt` | 116 |  | — |
| `ui/site/SiteTranslationsSection.kt` | 103 |  | — |
| `ui/site/content/PageContentDraft.kt` | 373 |  | — |
| `ui/site/content/PageContentEditor.kt` | 262 |  | — |
| `ui/site/content/ServicesDraft.kt` | 170 |  | — |
| `ui/site/content/ServicesEditor.kt` | 332 |  | — |
| `ui/site/position/MapMarkerIcons.kt` | 37 |  | — |
| `ui/site/position/PositionMap.kt` | 266 |  | — |
| `ui/site/position/PositionPickerDialog.kt` | 382 |  | — |
| `ui/site/position/PositionSection.kt` | 130 |  | — |
| `ui/site/position/PositionState.kt` | 94 |  | — |
| `ui/wizard/AppLevelSteps.kt` | 113 |  | — |
| `ui/wizard/NewCaseWizardScreen.kt` | 489 |  | — |
| `ui/wizard/WizardLogic.kt` | 68 |  | — |
| 🧪 `ui/cases/AppFieldsDraftTest.kt` | 62 |  | — |
| 🧪 `ui/cases/CaseLogicTest.kt` | 91 |  | — |
| 🧪 `ui/cases/CaseSaveLogicTest.kt` | 37 |  | — |
| 🧪 `ui/cases/SiteTrackTest.kt` | 41 |  | — |
| 🧪 `ui/invite/InviteFormatTest.kt` | 33 |  | — |
| 🧪 `ui/invite/InviteViewModelTest.kt` | 134 |  | — |
| 🧪 `ui/invite/PendingInviteTest.kt` | 24 | `SiciliaHostTests/OnboardingTests.swift` | scritto |
| 🧪 `ui/members/InviteFormTest.kt` | 104 |  | — |
| 🧪 `ui/members/MembersLogicTest.kt` | 71 |  | — |
| 🧪 `ui/property/CredentialsLogicTest.kt` | 33 |  | — |
| 🧪 `ui/property/PropertyManagementViewModelTest.kt` | 28 |  | — |
| 🧪 `ui/site/SiteDraftSaverTest.kt` | 46 |  | — |
| 🧪 `ui/site/SiteDraftTest.kt` | 389 |  | — |
| 🧪 `ui/site/content/PageContentDraftTest.kt` | 324 |  | — |
| 🧪 `ui/site/content/ServicesDraftTest.kt` | 204 |  | — |
| 🧪 `ui/site/position/PositionStateTest.kt` | 200 |  | — |
| 🧪 `ui/wizard/WizardLogicTest.kt` | 79 |  | — |
| `ui/cases/DeleteCase.kt` | 103 |  | — |
| `ui/wizard/importing/ImportStep.kt` | 258 |  | — |
| `ui/wizard/importing/ImportApply.kt` | 110 |  | — |
| `ui/wizard/importing/ImportViewModel.kt` | 175 |  | — |
| `ui/wizard/importing/OwnershipDeclaration.kt` | 9 |  | — |
| `ui/wizard/importing/ImportRepository.kt` | 75 |  | — |
| `ui/wizard/importing/ListingImport.kt` | 105 |  | — |
| `ui/wizard/importing/ImportUrls.kt` | 41 |  | — |
| `ui/wizard/importing/ImportReview.kt` | 52 |  | — |
| `ui/wizard/importing/ListingFetcher.kt` | 186 |  | — |
| 🧪 `ui/cases/DeleteCaseTest.kt` | 43 |  | — |
| 🧪 `ui/wizard/importing/ListingFetcherTest.kt` | 91 |  | — |
| 🧪 `ui/wizard/importing/ImportReviewTest.kt` | 30 |  | — |
| 🧪 `ui/wizard/importing/ImportUrlsTest.kt` | 39 |  | — |
| 🧪 `ui/wizard/importing/ImportApplyTest.kt` | 143 |  | — |
| 🧪 `ui/wizard/importing/PhotoProgressTest.kt` | 45 |  | — |
| 🧪 `ui/wizard/importing/OwnershipDeclarationTest.kt` | 20 |  | — |
| 🧪 `ui/wizard/importing/ListingImportTest.kt` | 107 |  | — |
| 🧪 `ui/wizard/importing/ImportRepositoryTest.kt` | 28 |  | — |

## F10 — Sfondo, notifiche e sincronizzazioni

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `services/LocalNotifier.kt` | 45 |  | — |
| `services/MyFirebaseMessagingService.kt` | 38 |  | — |
| `sync/BookingExcelReminderWorker.kt` | 49 |  | — |
| `sync/ICalSyncWorker.kt` | 251 | `Core/Logic/ICalSync.swift (parte pura: parseEvents, buildSyncPlan, safeErrorReason)` | parziale→F10 (download, scrittura, pianificazione) |
| 🧪 `sync/ICalSyncWorkerTest.kt` | 171 | `SiciliaHostTests/LogicTests.swift` | scritto |
| `services/NotificationChannels.kt` | 29 |  | — |

## F12 — Messaggi degli ospiti

| Android | Righe | iOS | Stato |
|---|---|---|---|
| `ui/messages/MessagesScreen.kt` | 391 |  | — |
| `ui/messages/MessagesViewModel.kt` | 204 |  | — |
| `ui/messages/MessagesFormat.kt` | 81 |  | — |
| 🧪 `ui/messages/MessagesFormatTest.kt` | 35 |  | — |

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
