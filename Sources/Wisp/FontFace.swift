import AppKit

/// Curated set of body fonts the user can pick from in the right-click
/// menu. All are preinstalled on macOS, all read well at 17–24pt body
/// sizes. Charter is the default — Matthew Carter's screen-optimised
/// serif. The rest cover different feels: warm humanist (Iowan Old
/// Style), classic refined (Hoefler Text, Palatino), and humanist sans
/// (Optima, Avenir Next) for those who don't want a serif at all.
enum FontFace: String, CaseIterable {
    case charter
    case iowanOldStyle
    case hoeflerText
    case palatino
    case optima
    case avenirNext

    var displayName: String {
        switch self {
        case .charter:        return "Charter"
        case .iowanOldStyle:  return "Iowan Old Style"
        case .hoeflerText:    return "Hoefler Text"
        case .palatino:       return "Palatino"
        case .optima:         return "Optima"
        case .avenirNext:     return "Avenir Next"
        }
    }

    /// Family name passed to NSFont(name:size:). NSFont accepts family
    /// names (not just PostScript names) and resolves to the regular
    /// face. If the family is missing, NSFont returns nil and we fall
    /// back through the chain in MinimalTextEditor.makeFont.
    var familyName: String { displayName }
}
