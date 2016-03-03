#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseCloudKitOptions : NSObject <NSCopying>

/**
 * You can configure the extension to pre-filter all but a subset of collections.
 *
 * The primary motivation for this is to reduce the overhead when first setting up the extension.
 * For example, if you're only syncing objects from a single collection,
 * then you could specify that collection here. So when the extension first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over all collections.
 * And enumerating a small subset of the entire database during initial setup can improve speed,
 * especially with larger databases.
 *
 * In addition to reducing the overhead during initial setup,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the GetRecordBlock will never be invoked, and the extension will act as if the block returned nil.
 *
 * For all rows whose collection is in the allowedCollections, the extension acts normally.
 * So the GetRecordBlock would still be invoked as normal.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;


// Todo: Need ability to set default options for CKModifyRecordsOperation

@end

NS_ASSUME_NONNULL_END
