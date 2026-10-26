import Foundation

/// English-keyed string lookup.
///
/// The development language is English, so the key doubles as the English
/// value; `Localizable.xcstrings` carries the zh-Hans translations and the
/// system picks the best match at runtime (anything else falls back to English).
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}
