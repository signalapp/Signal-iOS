#import "YapDatabaseOptions.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * This class provides extra configuration options that may be passed to YapDatabase.
 * The configuration options provided by this class are advanced (beyond the basic setup options).
**/
@implementation YapDatabaseOptions

@synthesize corruptAction = corruptAction;
@synthesize pragmaSynchronous = pragmaSynchronous;
@synthesize pragmaJournalSizeLimit = pragmaJournalSizeLimit;
#ifdef SQLITE_HAS_CODEC
@synthesize cipherKeyBlock = cipherKeyBlock;
#endif

- (id)init
{
	if ((self = [super init]))
	{
		corruptAction = YapDatabaseCorruptAction_Rename;
		pragmaSynchronous = YapDatabasePragmaSynchronous_Full;
		pragmaJournalSizeLimit = 0;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseOptions *copy = [[[self class] alloc] init];
	copy->corruptAction = corruptAction;
	copy->pragmaSynchronous = pragmaSynchronous;
	copy->pragmaJournalSizeLimit = pragmaJournalSizeLimit;
#ifdef SQLITE_HAS_CODEC
    copy.cipherKeyBlock = cipherKeyBlock;
#endif
	return copy;
}

@end
