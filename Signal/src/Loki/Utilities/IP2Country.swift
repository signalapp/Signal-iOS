import SwiftCSV

final class IP2Country {

    private static let ipv4Table = try! CSV(name: "GeoLite2-Country-Blocks-IPv4", extension: "csv", bundle: .main, delimiter: ",", encoding: .utf8, loadColumns: true)!
    private static let countryNamesTable = try! CSV(name: "GeoLite2-Country-Locations-English", extension: "csv", bundle: .main, delimiter: ",", encoding: .utf8, loadColumns: true)!
    private static var countryNamesCache: [String:String] = [:]

    // MARK: Lifecycle
    static let shared = IP2Country()

    private init() {
        preloadCountriesIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(preloadCountriesIfNeeded), name: .pathsBuilt, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Implementation
    static func getCountry(_ ip: String) -> String {
        var truncatedIP = ip
        func getCountryInternal() -> String {
            if let country = countryNamesCache[ip] { return country }
            if let ipv4TableIndex = ipv4Table.namedColumns["network"]!.firstIndex(where: { $0.starts(with: truncatedIP) }) {
                let countryID = ipv4Table.namedColumns["registered_country_geoname_id"]![ipv4TableIndex]
                if let countryNamesTableIndex = countryNamesTable.namedColumns["geoname_id"]!.firstIndex(of: countryID) {
                    let country = countryNamesTable.namedColumns["country_name"]![countryNamesTableIndex]
                    countryNamesCache[ip] = country
                    return country
                }
            }
            if truncatedIP.contains(".") && !truncatedIP.hasSuffix(".") { // The fuzziest we want to go is xxx.x
                truncatedIP.removeLast()
                if truncatedIP.hasSuffix(".") { truncatedIP.removeLast() }
                return getCountryInternal()
            } else {
                return "Unknown Country"
            }
        }
        return getCountryInternal()
    }

    @objc private func preloadCountriesIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            if OnionRequestAPI.paths.count < OnionRequestAPI.pathCount {
                let storage = OWSPrimaryStorage.shared()
                storage.dbReadConnection.read { transaction in
                    OnionRequestAPI.paths = storage.getOnionRequestPaths(in: transaction)
                }
            }
            guard OnionRequestAPI.paths.count >= OnionRequestAPI.pathCount else { return }
            let pathToDisplay = OnionRequestAPI.paths.first!
            pathToDisplay.forEach { snode in
                let _ = IP2Country.getCountry(snode.ip) // Preload if needed
            }
            print("[Loki] Finished preloading onion request path countries.")
        }
    }
}
