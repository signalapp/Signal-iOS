// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

extension Storage{
    
    private static let recentSearchResultDatabaseCollection = "RecentSearchResultDatabaseCollection"
    private static let recentSearchResultKey = "RecentSearchResult"
    
    public func getRecentSearchResults() -> [String] {
        var result: [String]?
        Storage.read { transaction in
            result = transaction.object(forKey: Storage.recentSearchResultKey, inCollection: Storage.recentSearchResultDatabaseCollection) as? [String]
        }
        return result ?? []
    }
    
    public func clearRecentSearchResults() {
        Storage.write { transaction in
            transaction.removeObject(forKey: Storage.recentSearchResultKey, inCollection: Storage.recentSearchResultDatabaseCollection)
        }
    }
    
    public func addSearchResults(threadID: String) -> [String] {
        var recentSearchResults = getRecentSearchResults()
        if recentSearchResults.count > 20 { recentSearchResults.remove(at: 0) } // Limit the size of the collection to 20
        if let index = recentSearchResults.firstIndex(of: threadID) { recentSearchResults.remove(at: index) }
        recentSearchResults.append(threadID)
        Storage.write { transaction in
            transaction.setObject(recentSearchResults, forKey: Storage.recentSearchResultKey, inCollection: Storage.recentSearchResultDatabaseCollection)
        }
        return recentSearchResults
    }
}
