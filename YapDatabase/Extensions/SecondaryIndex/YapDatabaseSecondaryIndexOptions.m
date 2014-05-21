#import "YapDatabaseSecondaryIndexOptions.h"

/**
 * Welcome to YapDatabase!
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * This class provides extra options when initializing YapDatabaseSecondaryIndex.
 *
 * For more information, see the wiki article about secondary indexes:
 * https://github.com/yaptv/YapDatabase/wiki/Secondary-Indexes
**/
@implementation YapDatabaseSecondaryIndexOptions

@synthesize allowedCollections = allowedCollections;

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseSecondaryIndexOptions *copy = [[YapDatabaseSecondaryIndexOptions alloc] init];
	copy->allowedCollections = allowedCollections;
	
	return copy;
}

@end
