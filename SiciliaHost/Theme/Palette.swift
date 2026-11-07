import SwiftUI
import UIKit

// Palette Sicilia Host — porting di `theme/Color.kt` e `Theme.kt` dell'app Android.
//
// I tre colori del fico d'India del logo sono fissi e non si toccano: verde pala, giallo fiore, rosso frutto. Tutto il
// resto è una rampa costruita attorno a quelle tre tinte (contrasto e gerarchia, non nuovi colori di brand).
//
// I tre colori valgono anche come linguaggio di stato, perché l'app ha esattamente tre stati ovunque:
//   verde  = confermato   (check-in, saldo positivo, scorte ok)
//   giallo = da rivedere  (da completare, scorta bassa, in attesa)
//   rosso  = in uscita    (check-out, spesa, esaurito, errore)
// Le schermate li leggono da `Theme.primary` / `Theme.secondary` / `Theme.error`, non dalle costanti di `Brand`
// (le uniche eccezioni sono il login con il suo gradiente fisso e il riquadro dello scanner sopra la fotocamera).

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// Colore che segue il tema chiaro/scuro del sistema.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Valori fissi del marchio e rampe di tinte (esadecimali RGB).
enum Brand {
    // Verde — primario
    static let green: UInt32 = 0x3C9650 // brand, non modificare
    static let green900: UInt32 = 0x0F2A18
    static let green700: UInt32 = 0x285532
    static let green600: UInt32 = 0x2F7A41
    static let green400: UInt32 = 0x65A757
    static let green200: UInt32 = 0xA9D6B4
    static let green100: UInt32 = 0xDCEEE1

    // Giallo — secondario. Su fondo chiaro il giallo di brand non ha contrasto per il testo: riempimento con testo
    // scuro sopra, oppure pastiglia/indicatore. Per testo giallo su fondo chiaro: yellow700.
    static let yellow: UInt32 = 0xF0C607 // brand, non modificare
    static let yellow800: UInt32 = 0x4A3B02
    static let yellow700: UInt32 = 0x7A6103
    static let yellow300: UInt32 = 0xF7DE6B
    static let yellow100: UInt32 = 0xFCF2C8

    // Rosso — terziario / errore
    static let red: UInt32 = 0xB7332D // brand, non modificare
    static let red800: UInt32 = 0x4E1512
    static let red700: UInt32 = 0x7F2320
    static let red300: UInt32 = 0xE2938E
    static let red100: UInt32 = 0xF8E1DF

    // Neutri caldi: l'inchiostro è il nero del contorno del logo; i fondi restano sabbia, non grigio di sistema.
    static let ink: UInt32 = 0x151515
    static let light: UInt32 = 0xFAF7F1

    // Livelli di superficie chiari (sabbia) e scuri (inchiostro)
    static let sandLowest: UInt32 = 0xFFFFFF, sandLow: UInt32 = 0xF5F1E8, sand: UInt32 = 0xEFEADF
    static let sandHigh: UInt32 = 0xE8E2D5, sandHighest: UInt32 = 0xE1DACB
    static let sandOnVariant: UInt32 = 0x5A5347, sandOutline: UInt32 = 0xA8A090, sandOutlineVariant: UInt32 = 0xD3CCBC
    static let inkLowest: UInt32 = 0x0D0D0B, inkLow: UInt32 = 0x1A1A17, inkSurface: UInt32 = 0x1E1E1B
    static let inkHigh: UInt32 = 0x292925, inkHighest: UInt32 = 0x34342F
    static let inkOnVariant: UInt32 = 0xCCC5B6, inkOutline: UInt32 = 0x918A7B, inkOutlineVariant: UInt32 = 0x494339
}

/// Ruoli di colore dell'app (equivalente del `ColorScheme` di Material 3 usato dall'Android), chiaro e scuro.
enum Theme {
    // Primario (verde = confermato)
    static let primary = Color(light: Brand.green, dark: Brand.green400)
    static let onPrimary = Color(light: 0xFFFFFF, dark: Brand.green900)
    static let primaryContainer = Color(light: Brand.green100, dark: Brand.green700)
    static let onPrimaryContainer = Color(light: Brand.green900, dark: Brand.green100)

    // Secondario (giallo = da rivedere)
    static let secondary = Color(light: Brand.yellow700, dark: Brand.yellow300)
    static let onSecondary = Color(light: 0xFFFFFF, dark: Brand.yellow800)
    static let secondaryContainer = Color(light: Brand.yellow100, dark: Brand.yellow800)
    static let onSecondaryContainer = Color(light: Brand.yellow800, dark: Brand.yellow100)

    // Errore / terziario (rosso = in uscita)
    static let error = Color(light: Brand.red, dark: Brand.red300)
    static let onError = Color(light: 0xFFFFFF, dark: Brand.red800)
    static let errorContainer = Color(light: Brand.red100, dark: Brand.red700)
    static let onErrorContainer = Color(light: Brand.red800, dark: Brand.red100)

    // Fondi e testo
    static let background = Color(light: Brand.light, dark: Brand.ink)
    static let onBackground = Color(light: Brand.ink, dark: Brand.light)
    static let onSurface = onBackground
    static let onSurfaceVariant = Color(light: Brand.sandOnVariant, dark: Brand.inkOnVariant)

    // Livelli di superficie (card, dialog, barre): vanno sempre dichiarati tutti, come sull'Android.
    static let surfaceContainerLowest = Color(light: Brand.sandLowest, dark: Brand.inkLowest)
    static let surfaceContainerLow = Color(light: Brand.sandLow, dark: Brand.inkLow)
    static let surfaceContainer = Color(light: Brand.sand, dark: Brand.inkSurface)
    static let surfaceContainerHigh = Color(light: Brand.sandHigh, dark: Brand.inkHigh)
    static let surfaceContainerHighest = Color(light: Brand.sandHighest, dark: Brand.inkHighest)

    static let outline = Color(light: Brand.sandOutline, dark: Brand.inkOutline)
    static let outlineVariant = Color(light: Brand.sandOutlineVariant, dark: Brand.inkOutlineVariant)

    /// Giallo pieno del logo per riempimenti con testo scuro sopra (mai per testo su fondo chiaro).
    static let yellowFill = Color(hex: Brand.yellow)
}

/// Raggi degli angoli: più stretti dei default, le schede sono basse (un raggio grande su una card bassa la fa
/// sembrare una pillola). Stesso `Shapes` dell'Android.
enum Radius {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    /// Forma dei pulsanti con testo: più morbida dei 12 delle card, meno di una pillola.
    static let button: CGFloat = 16
    static let dialog: CGFloat = 28
}

func roundedShape(_ radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

/// Misure di densità dell'app, in un posto solo (stesse di `theme/Dimens.kt`).
enum Dimens {
    /// Margine esterno della schermata.
    static let screenPadding: CGFloat = 12
    /// Padding interno di card e righe di lista: decide l'altezza della scheda.
    static let cardPadding: CGFloat = 10
    /// Distanza tra elementi contigui di una lista.
    static let itemSpacing: CGFloat = 6
    /// Distanza tra blocchi diversi della stessa schermata.
    static let sectionSpacing: CGFloat = 14
    /// Icona dentro una riga di lista o un bottone compatto.
    static let iconSmall: CGFloat = 18
    /// Icona guida a inizio riga (avatar/stato).
    static let iconMedium: CGFloat = 28
    /// Altezza dei campi e dei bottoni compatti.
    static let controlHeight: CGFloat = 40
    /// Spazio da lasciare in fondo alle liste per non finire sotto la barra flottante.
    static let bottomBarInset: CGFloat = 72
}
