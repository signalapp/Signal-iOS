#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"

/**
 * Welcome to YapDatabase!
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * This class provides extra options when initializing YapDatabaseRTreeIndex.
 *
 * For more information, see the wiki article about secondary indexes:
 * https://github.com/yapstudios/YapDatabase/wiki/Secondary-Indexes
**/
@interface YapDatabaseRTreeIndexOptions : NSObject <NSCopying>

/**
 * You can configure the extension to pre-filter all but a subset of collections.
 *
 * The primary motivation for this is to reduce the overhead when first populating the rtree index table.
 * For example, if you're creating a rtree index from a single collection,
 * then you could specify that collection here. So when the extension first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over the entire database.
 * And enumerating a small subset of the entire database during population can improve speed,
 * especially with larger databases.
 *
 * In addition to reducing the overhead when first populating the extension,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the rTreeIndexBlock will never be invoked,
 * and the extension will act as if the rTreeIndexBlock left the dictionary empty.
 *
 * For all rows whose collection is in the allowedCollections, the extension acts normally.
 * So the rTreeIndexBlock would still be invoked as normal.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;

@end
