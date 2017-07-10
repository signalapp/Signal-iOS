#import "YapDatabaseManager.h"
#import "YapDatabaseAtomic.h"

/**
 * There should only be one YapDatabase or YapCollectionDatabase per file.
 *
 * The architecture design is to create a single parent database instance,
 * and then spawn connections to the database as needed from the parent.
 *
 * The architecture is built around this restriction, and is dependent upon it for proper operation.
 * This class simply helps maintain this requirement.
**/
@implementation YapDatabaseManager

static NSMutableSet *registeredPaths;
static YAPUnfairLock lock;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		registeredPaths = [[NSMutableSet alloc] init];
		lock = YAP_UNFAIR_LOCK_INIT;
	});
}

+ (BOOL)registerDatabaseForPath:(NSString *)path
{
	if (path == nil) return NO;
	
	// Note: The path has already been standardized by the caller (path = [inPath stringByStandardizingPath]).
	
	BOOL result = NO;
	
	YAPUnfairLockLock(&lock);
	if (![registeredPaths containsObject:path])
	{
		[registeredPaths addObject:path];
		result = YES;
	}
	YAPUnfairLockUnlock(&lock);
	
	return result;
}

+ (void)deregisterDatabaseForPath:(NSString *)inPath
{
	NSString *path = [inPath stringByStandardizingPath];
	if (path == nil) return;
	
	YAPUnfairLockLock(&lock);
	[registeredPaths removeObject:path];
	YAPUnfairLockUnlock(&lock);
}

@end
