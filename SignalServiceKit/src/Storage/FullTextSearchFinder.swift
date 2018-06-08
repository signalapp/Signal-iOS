//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class FullTextSearchFinder: NSObject {

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any) -> Void) {
        guard let ext = ext(transaction: transaction) else {
            assertionFailure("ext was unexpectedly nil")
            return
        }

        ext.enumerateKeysAndObjects(matching: searchText) { (_, _, object, _) in
            block(object)
        }
    }

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.ext(FullTextSearchFinder.dbExtensionName) as? YapDatabaseFullTextSearchTransaction
    }

    // MARK: - Extension Registration

    private static let dbExtensionName: String = "FullTextSearchFinderExtension"

    @objc
    public class func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    public class func syncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }

    private class var dbExtensionConfig: YapDatabaseFullTextSearch {
        let contentColumnName = "content"
        let handler = YapDatabaseFullTextSearchHandler.withObjectBlock { (dict: NSMutableDictionary, _: String, _: String, object: Any) in
            if let groupThread = object as? TSGroupThread {
                dict[contentColumnName] = groupThread.groupModel.groupName
            }
        }

        // update search index on contact name changes?
        // update search index on message insertion?

        // TODO is it worth doing faceted search, i.e. Author / Name / Content?
        // seems unlikely that mobile users would use the "author: Alice" search syntax.
        return YapDatabaseFullTextSearch(columnNames: ["content"], handler: handler)
    }
}
