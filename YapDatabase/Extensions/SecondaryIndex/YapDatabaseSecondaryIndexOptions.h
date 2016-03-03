#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 * 
 * This class provides extra options when initializing YapDatabaseSecondaryIndex.
 * 
 * For more information, see the wiki article about secondary indexes:
 * https://github.com/yapstudios/YapDatabase/wiki/Secondary-Indexes
**/
@interface YapDatabaseSecondaryIndexOptions : NSObject <NSCopying>

/**
 * You can configure the extension to pre-filter all but a subset of collections.
 *
 * The primary motivation for this is to reduce the overhead when first populating the secondary index table.
 * For example, if you're creating secondary indexes from a single collection,
 * then you could specify that collection here. So when the extension first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over the entire database.
 * And enumerating a small subset of the entire database during population can improve speed,
 * especially with larger databases.
 *
 * In addition to reducing the overhead when first populating the extension,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the secondaryIndexBlock will never be invoked,
 * and the extension will act as if the secondaryIndexBlock left the dictionary empty.
 *
 * For all rows whose collection is in the allowedCollections, the extension acts normally.
 * So the secondaryIndexBlock would still be invoked as normal.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;

@end

NS_ASSUME_NONNULL_END
