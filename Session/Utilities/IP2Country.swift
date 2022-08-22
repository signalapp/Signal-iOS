import Foundation
import GRDB
import SessionSnodeKit

final class IP2Country {
    var countryNamesCache: [String:String] = [:]

    private static let workQueue = DispatchQueue(label: "IP2Country.workQueue", qos: .utility) // It's important that this is a serial queue
    static var isInitialized = false
    
    // MARK: Tables
    /// This table has two columns: the "network" column and the "registered_country_geoname_id" column. The network column contains the **lower** bound of an IP
    /// range and the "registered_country_geoname_id" column contains the ID of the country corresponding to that range. We look up an IP by finding the first index in the
    /// network column where the value is greater than the IP we're looking up (converted to an integer). The IP we're looking up must then be in the range **before** that
    /// range.
    private lazy var ipv4Table: [String:[Int]] = {
        let url = Bundle.main.url(forResource: "GeoLite2-Country-Blocks-IPv4", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [String:[Int]]
    }()
    
    private lazy var countryNamesTable: [String:[String]] = {
        let url = Bundle.main.url(forResource: "GeoLite2-Country-Locations-English", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [String:[String]]
    }()

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
        if let result = countryNamesCache[ip] { return result }
        let ipAsInt = IPv4.toInt(ip)
        guard let ipv4TableIndex = given(ipv4Table["network"]!.firstIndex(where: { $0 > ipAsInt }), { $0 - 1 }) else { return "Unknown Country" } // Relies on the array being sorted
        let countryID = ipv4Table["registered_country_geoname_id"]![ipv4TableIndex]
        guard let countryNamesTableIndex = countryNamesTable["geoname_id"]!.firstIndex(of: String(countryID)) else { return "Unknown Country" }
        let result = countryNamesTable["country_name"]![countryNamesTableIndex]
        countryNamesCache[ip] = result
        return result
    }

    @objc func populateCacheIfNeededAsync() {
        // This has to be sync since the `countryNamesCache` dict doesn't like async access
        IP2Country.workQueue.sync { [weak self] in
            _ = self?.populateCacheIfNeeded()
        }
    }

    func populateCacheIfNeeded() -> Bool {
        guard let pathToDisplay: [Snode] = OnionRequestAPI.paths.first else { return false }
        
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
