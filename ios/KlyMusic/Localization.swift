import Foundation

struct ListeningLocale: Equatable, Sendable {
    let languageCode: String
    let countryCode: String
    var cacheKey: String { languageCode + "-" + countryCode }

    static var current: ListeningLocale {
        resolve(preferredLanguages: Locale.preferredLanguages, regionCode: Locale.current.region?.identifier)
    }

    static func resolve(preferredLanguages: [String], regionCode: String?) -> ListeningLocale {
        let locale = Locale(identifier: preferredLanguages.first ?? "en-US")
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        // Turkish listening preferences follow the phone language, even when its region is abroad.
        if language == "tr" { return ListeningLocale(languageCode: "tr", countryCode: "tr") }
        let defaultCountries = ["en": "us", "az": "az", "de": "de", "fr": "fr", "es": "es", "it": "it", "pt": "br", "ja": "jp", "ko": "kr", "ar": "sa", "ru": "ru"]
        let country = locale.region?.identifier.lowercased() ?? defaultCountries[language] ?? regionCode?.lowercased() ?? "us"
        return ListeningLocale(languageCode: language, countryCode: country)
    }
}

enum AppLanguage {
    static var current: String {
        resolve(selection: UserDefaults.standard.string(forKey: "language"), preferredLanguages: Locale.preferredLanguages)
    }
    static func resolve(selection: String?, preferredLanguages: [String]) -> String {
        if let selection, ["tr", "en"].contains(selection) { return selection }
        return ListeningLocale.resolve(preferredLanguages: preferredLanguages, regionCode: nil).languageCode == "tr" ? "tr" : "en"
    }
}

func L(_ key: String) -> String {
    let language = AppLanguage.current
    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
