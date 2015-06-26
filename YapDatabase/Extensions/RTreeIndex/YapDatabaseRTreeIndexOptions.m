#import "YapDatabaseRTreeIndexOptions.h"

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
 * https://github.com/yapstudios/YapDatabase/wiki/RTree-Indexes
**/
@implementation YapDatabaseRTreeIndexOptions

@synthesize allowedCollections = allowedCollections;

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseRTreeIndexOptions *copy = [[YapDatabaseRTreeIndexOptions alloc] init];
	copy->allowedCollections = allowedCollections;

	return copy;
}

@end
