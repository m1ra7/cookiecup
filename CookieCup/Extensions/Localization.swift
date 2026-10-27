import SwiftUI

struct Copy {
    let language: String
    var locale: Locale { Locale(identifier: language) }
    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    func money(_ cents: Int) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR").locale(locale)) }
}
private struct CopyKey: EnvironmentKey { static let defaultValue = Copy(language: "en") }
extension EnvironmentValues { var copy: Copy { get { self[CopyKey.self] } set { self[CopyKey.self] = newValue } } }
