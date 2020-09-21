
final class IP2Country {
    var countryNamesCache: [String:String] = [:]

    private lazy var ipv4Table = try! CSV(name: "GeoLite2-Country-Blocks-IPv4", extension: "csv", bundle: .main, delimiter: ",", encoding: .utf8, loadColumns: true)!
    private lazy var countryNamesTable = try! CSV(name: "GeoLite2-Country-Locations-English", extension: "csv", bundle: .main, delimiter: ",", encoding: .utf8, loadColumns: true)!

    private static let workQueue = DispatchQueue(label: "IP2Country.workQueue", qos: .utility) // It's important that this is a serial queue

    static var isInitialized = false

    // MARK: Lifecycle
    static let shared = IP2Country()

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(populateCacheIfNeededAsync), name: .pathsBuilt, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Implementation
    private func cacheCountry(for ip: String) -> String {
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

    @objc func populateCacheIfNeededAsync() {
        IP2Country.workQueue.async {
            let _ = self.populateCacheIfNeeded()
        }
    }

    func populateCacheIfNeeded() -> Bool {
        if OnionRequestAPI.paths.count < OnionRequestAPI.pathCount {
            let storage = OWSPrimaryStorage.shared()
            storage.dbReadConnection.read { transaction in
                OnionRequestAPI.paths = storage.getOnionRequestPaths(in: transaction)
            }
        }
        let paths = OnionRequestAPI.paths
        guard paths.count >= OnionRequestAPI.pathCount else { return false }
        let pathToDisplay = paths.first!
        pathToDisplay.forEach { snode in
            let _ = self.cacheCountry(for: snode.ip) // Preload if needed
        }
        DispatchQueue.main.async {
            IP2Country.isInitialized = true
            NotificationCenter.default.post(name: .onionRequestPathCountriesLoaded, object: nil)
        }
        print("[Loki] Finished preloading onion request path countries.")
        return true
    }
}
