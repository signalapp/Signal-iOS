
final class IP2Country {
    var countryNamesCache: [String:String] = [:]

    private lazy var ipv4Table: [String:[String]] = {
        let url = Bundle.main.url(forResource: "GeoLite2-Country-Blocks-IPv4", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [String:[String]]
    }()
    
    private lazy var countryNamesTable: [String:[String]] = {
        let url = Bundle.main.url(forResource: "GeoLite2-Country-Locations-English", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [String:[String]]
    }()

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
            if let ipv4TableIndex = ipv4Table["network"]!.firstIndex(where: { $0.starts(with: truncatedIP) }) {
                let countryID = ipv4Table["registered_country_geoname_id"]![ipv4TableIndex]
                if let countryNamesTableIndex = countryNamesTable["geoname_id"]!.firstIndex(of: countryID) {
                    let country = countryNamesTable["country_name"]![countryNamesTableIndex]
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
        if OnionRequestAPI.paths.isEmpty {
            OnionRequestAPI.paths = Storage.shared.getOnionRequestPaths()
        }
        let paths = OnionRequestAPI.paths
        guard !paths.isEmpty else { return false }
        let pathToDisplay = paths.first!
        pathToDisplay.forEach { snode in
            let _ = self.cacheCountry(for: snode.ip) // Preload if needed
        }
        DispatchQueue.main.async {
            IP2Country.isInitialized = true
            NotificationCenter.default.post(name: .onionRequestPathCountriesLoaded, object: nil)
        }
        SNLog("Finished preloading onion request path countries.")
        return true
    }
}
