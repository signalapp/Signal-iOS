#import "YDBCKMergeInfo.h"
#import "YapDatabaseCloudKitPrivate.h"


@implementation YDBCKMergeInfo
{
	NSMutableDictionary *originalValues;
}

// See header file for documentation

@dynamic originalValues;

@synthesize pendingLocalRecord = pendingLocalRecord;
@synthesize updatedPendingLocalRecord = updatedPendingLocalRecord;

- (NSDictionary *)originalValues
{
	return originalValues;
}

// Private API

- (void)mergeNewerRecord:(CKRecord *)newerRecord newerOriginalValues:(NSDictionary *)newerOriginalValues
{
	// Merge into pendingLocalRecord
	//
	// Note: For pendingLocalRecord, the most recent value wins.
	
	if (newerRecord)
	{
		for (NSString *changedKey in newerRecord.changedKeys)
		{
			// Remember: nil is a valid value.
			// It indicates removal of the value for the key, which is a valid action.
			
			id value = [newerRecord objectForKey:changedKey];
			[pendingLocalRecord setObject:value forKey:changedKey];
		}
	}
	
	// Merge into originalValues
	//
	// Note: For originalValues, the least recent value wins.
	
	if (newerOriginalValues)
	{
		if (originalValues == nil)
		{
			originalValues = [newerOriginalValues mutableCopy];
		}
		else
		{
			[newerOriginalValues enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
				
				if ([originalValues objectForKey:key] == nil)
				{
					[originalValues setObject:obj forKey:key];
				}
			}];
		}
	}
}

@end
