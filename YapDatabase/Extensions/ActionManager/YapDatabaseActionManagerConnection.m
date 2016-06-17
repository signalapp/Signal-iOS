#import "YapDatabaseActionManagerConnection.h"
#import "YapDatabaseActionManagerPrivate.h"


@implementation YapDatabaseActionManagerConnection

- (id)initWithParent:(YapDatabaseView *)inParent databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super initWithParent:inParent databaseConnection:inDbC]))
	{
		actionItemsCache = [[YapCache alloc] initWithCountLimit:100];
		actionItemsCache.allowedKeyClasses = [NSSet setWithObject:[YapCollectionKey class]];
		actionItemsCache.allowedObjectClasses = [NSSet setWithObjects:[NSArray class], [NSNull class], nil];
	}
	return self;
}

- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseActionManagerTransaction *extTransaction =
	  [[YapDatabaseActionManagerTransaction alloc] initWithParentConnection:self
	                                                    databaseTransaction:databaseTransaction];
	
	return extTransaction;
}

- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseActionManagerTransaction *extTransaction =
	  [[YapDatabaseActionManagerTransaction alloc] initWithParentConnection:self
	                                                    databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return extTransaction;
}

- (void)postRollbackCleanup
{
	[actionItemsCache removeAllObjects];
	[super postRollbackCleanup];
}

/**
 * YapDatabaseExtensionConnection subclasses may OPTIONALLY implement this method.
 *
 * The default implementation likely does the right thing for most extensions.
 * That is, most extensions only need the information they store in the changeset.
 * However, the full changeset also contains information about what was changed in the main database table:
 * - YapDatabaseObjectChangesKey
 * - YapDatabaseMetadataChangesKey
 * - YapDatabaseRemovedKeysKey
 * - YapDatabaseRemovedCollectionsKey
 * - YapDatabaseAllKeysRemovedKey
 * 
 * So if the extension needs this information, it's better to re-use what's already available,
 * rather than have the extension duplicate the same information within its local changeset.
 * 
 * @param changeset
 *   The FULL changeset dictionary, including the core changeset info,
 *   as well as the changeset info for every registered extension.
 * 
 * @param registeredName
 *   The registeredName of the extension.
 *   This is the same as parent.registeredName, and is simply passed as a convenience.
**/
- (void)noteCommittedChangeset:(NSDictionary *)changeset registeredName:(NSString *)registeredName
{
	// Update our actionItemsCache
	
	NSDictionary<YapCollectionKey *, id> *objectChanges   =  [changeset objectForKey:YapDatabaseObjectChangesKey];
	
	NSSet<YapCollectionKey *> *removedKeys        = [changeset objectForKey:YapDatabaseRemovedKeysKey];
	NSSet<NSString *>         *removedCollections = [changeset objectForKey:YapDatabaseRemovedCollectionsKey];
	
	BOOL databaseCleared = [[changeset objectForKey:YapDatabaseAllKeysRemovedKey] boolValue];
	
	if (databaseCleared)
	{
		[actionItemsCache removeAllObjects];
	}
	else
	{
		for (YapCollectionKey *ck in [objectChanges keyEnumerator])
		{
			[actionItemsCache removeObjectForKey:ck];
		}
		
		for (YapCollectionKey *ck in removedKeys)
		{
			[actionItemsCache removeObjectForKey:ck];
		}
		
		if (removedCollections.count > 0)
		{
			NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:[actionItemsCache count]];
			
			[actionItemsCache enumerateKeysWithBlock:^(YapCollectionKey *ck, BOOL * _Nonnull stop) {
				
				if ([removedCollections containsObject:ck.collection])
				{
					[keysToRemove addObject:ck];
				}
			}];
			
			if (keysToRemove.count > 0)
			{
				[actionItemsCache removeObjectsForKeys:keysToRemove];
			}
		}
	}
	
	// Update the underlying view
	
	[super noteCommittedChangeset:changeset registeredName:registeredName];
}

@end
