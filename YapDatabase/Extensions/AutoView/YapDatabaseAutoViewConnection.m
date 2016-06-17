#import "YapDatabaseAutoViewConnection.h"

#import "YapDatabaseAutoViewPrivate.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabasePrivate.h"

#import "YapCollectionKey.h"
#import "YapCache.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@interface YapDatabaseAutoView ()

/**
 * This method is designed exclusively for YapDatabaseViewConnection.
 * All subclasses and transactions are required to use our version of the same method.
 *
 * So we declare it here, as opposed to within YapDatabaseViewPrivate.
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseAutoViewConnection

#pragma mark Properties

- (YapDatabaseAutoView *)autoView
{
	return (YapDatabaseAutoView *)parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseAutoViewTransaction *transaction =
	  [[YapDatabaseAutoViewTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseAutoViewTransaction *transaction =
	  [[YapDatabaseAutoViewTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	[super postCommitCleanup];
	
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	grouping = nil;
	sorting = nil;
	
	groupingChanged = NO;
	sortingChanged = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	[super postRollbackCleanup];
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	grouping = nil;
	sorting = nil;
	
	groupingChanged = NO;
	sortingChanged = NO;
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	[super getInternalChangeset:&internalChangeset
	          externalChangeset:&externalChangeset
	             hasDiskChanges:&hasDiskChanges];
	
	if (groupingChanged || sortingChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if (groupingChanged) {
			internalChangeset[changeset_key_grouping] = grouping;
		}
		if (sortingChanged) {
			internalChangeset[changeset_key_sorting] = sorting;
		}
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Inspection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Gets an exact list of changes that happend to the view, translating groups to sections as requested.
 * See the header file for more information.
**/
- (void)getSectionChanges:(NSArray<YapDatabaseViewSectionChange *> **)sectionChangesPtr
               rowChanges:(NSArray<YapDatabaseViewRowChange *> **)rowChangesPtr
         forNotifications:(NSArray *)notifications
             withMappings:(YapDatabaseViewMappings *)mappings
{
	if (mappings == nil)
	{
		YDBLogWarn(@"%@ - mappings parameter is nil", THIS_METHOD);
		
		if (sectionChangesPtr) *sectionChangesPtr = nil;
		if (rowChangesPtr) *rowChangesPtr = nil;
		
		return;
	}
	if (mappings.snapshotOfLastUpdate == UINT64_MAX)
	{
		NSString *reason = [NSString stringWithFormat:
		    @"ViewConnection[%p, RegisteredName=%@] was asked for changes, but given bad mappings.",
			self, parent.registeredName];
		
		NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
		    @"The given mappings have not been properly initialized."
			@" You need to invoke [mappings updateWithTransaction:transaction] once in order to initialize"
			@" the mappings object. You should do this after invoking"
			@" [databaseConnection beginLongLivedReadTransaction]. For example code, please see"
			@" YapDatabaseViewMappings.h, or see the wiki: https://github.com/yapstudios/YapDatabase/wiki/Views"};
	
		@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	}
	
	if ([notifications count] == 0)
	{
		if (sectionChangesPtr) *sectionChangesPtr = nil;
		if (rowChangesPtr) *rowChangesPtr = nil;
		
		return;
	}
	
	NSString *registeredName = parent.registeredName;
	NSMutableArray *all_changes = [NSMutableArray arrayWithCapacity:[notifications count]];
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:changeset_key_changes];
		
		[all_changes addObjectsFromArray:changeset_changes];
	}
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Getting an exception here about not being in a longLivedReadTransaction?
		//
		// The databaseConnection needs to be in a longLivedReadTransaction in order to guarantee"
		// (A) you can provide a stable data-source for your UI thread and
		// (B) you can get changesets which match the movement from one stable data-source state to another.
		//
		// If you think your databaseConnection IS in a longLivedReadTransaction,
		// then perhaps you aborted it by accident.
		// This generally happens when you use a databaseConnection,
		// which is in a longLivedReadTransaction, to perform a read-write transaction.
		// Doing so implicitly forces the connection out of the longLivedReadTransaction,
		// and moves it to the most recent snapshot. If this is the case,
		// be sure to use a separate connection for your read-write transaction.
		//
		[mappings updateWithTransaction:transaction forceUpdateRangeOptions:NO];
	}];
	
	NSDictionary *firstChangeset = [[notifications objectAtIndex:0] userInfo];
	NSDictionary *lastChangeset = [[notifications lastObject] userInfo];
	
	uint64_t firstSnapshot = [[firstChangeset objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
	uint64_t lastSnapshot  = [[lastChangeset  objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
	
	if ((originalMappings.snapshotOfLastUpdate != (firstSnapshot - 1)) ||
	    (mappings.snapshotOfLastUpdate != lastSnapshot))
	{
		NSString *reason = [NSString stringWithFormat:
		  @"ViewConnection[%p, RegisteredName=%@] was asked for changes,"
		  @" but given mismatched mappings & notifications.", self, parent.registeredName];
		
		NSString *failureReason = [NSString stringWithFormat:
		  @"preMappings.snapshotOfLastUpdate: expected(%llu) != found(%llu), "
		  @"postMappings.snapshotOfLastUpdate: expected(%llu) != found(%llu), ",
			(firstSnapshot - 1), originalMappings.snapshotOfLastUpdate,
			lastSnapshot, mappings.snapshotOfLastUpdate];
		
		NSString *suggestion = [NSString stringWithFormat:
		  @"When you initialize the database, the snapshot (uint64) is set to zero."
		  @" Every read-write transaction (that makes modifications) increments the snapshot."
		  @" Now, when you ask the viewConnection for a changeset, "
		  @" you need to pass matching mappings & notifications. That is, the mappings need to represent the"
		  @" database at snapshot X, and the notifications need to represent the database at snapshots"
		  @" @[ X+1, X+2, ...]. This does not appear to be the case. This most often happens when the"
		  @" databaseConnection isn't using a longLivedReadTransaction. And this happens by accident"
		  @" most often when you use a databaseConnection, which is in a longLivedReadTransaction, to perform"
		  @" a read-write transaction. Doing so implicitly forces the connection out of the"
		  @" longLivedReadTransaction, and moves it to the most recent snapshot. If this is the case,"
		  @" be sure to use a separate connection for your read-write transaction."];
		
		NSDictionary *userInfo = @{
			NSLocalizedFailureReasonErrorKey: failureReason,
			NSLocalizedRecoverySuggestionErrorKey: suggestion };
	
		// If we don't throw the exception here,
		// then you'll just get an exception later from the tableView or collectionView.
		// It will look something like this:
		//
		// > Invalid update: invalid number of rows in section X. The number of rows contained in an
		// > existing section after the update (Y) must be equal to the number of rows contained in that section
		// > before the update (Z), plus or minus the number of rows inserted or deleted from that
		// > section (# inserted, # deleted).
		//
		// In order to guarantee you DON'T get an exception (either from YapDatabase or from Apple),
		// then you need to follow the instructions for setting up your connection, mappings, & notifications.
		//
		// For complete code samples, check out the wiki:
		// https://github.com/yapstudios/YapDatabase/wiki/Views
		//
		// You may be tempted to simply comment out the exception below.
		// If you do, you're not fixing the root cause of your problem.
		// Furthermore, you're simply trading this exception, which comes with documented steps on how
		// to fix the problem, for an exception from Apple which will be even harder to diagnose.
		
		NSException *exception =
		  [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
		
		YDBLogError(@"Throwing exception: %@\n  - FailureReason: %@\n  - RecoverySuggestion: %@",
		            exception, failureReason, suggestion);
		
		// For more help, go here:
		// https://github.com/yapstudios/YapDatabase/wiki/Views#managing-mappings
		@throw exception;
	}
	
	[YapDatabaseViewChange getSectionChanges:sectionChangesPtr
	                              rowChanges:rowChangesPtr
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:all_changes];
}

/**
 * A simple YES/NO query to see if the view changed at all, inclusive of all groups.
**/
- (BOOL)hasChangesForNotifications:(NSArray *)notifications
{
	NSString *registeredName = parent.registeredName;
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:changeset_key_changes];
		
		if ([changeset_changes count] > 0)
		{
			return YES;
		}
	}
	
	return NO;
}

/**
 * A simple YES/NO query to see if a particular group within the view changed at all.
**/
- (BOOL)hasChangesForGroup:(NSString *)group inNotifications:(NSArray *)notifications
{
	if (group == nil) return NO;
	
	NSString *registeredName = parent.registeredName;
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:changeset_key_changes];
		
		for (id change in changeset_changes)
		{
			if ([change isKindOfClass:[YapDatabaseViewSectionChange class]])
			{
				__unsafe_unretained YapDatabaseViewSectionChange *sectionChange =
				  (YapDatabaseViewSectionChange *)change;
				
				if ([sectionChange->group isEqualToString:group])
				{
					return YES;
				}
			}
			else
			{
				__unsafe_unretained YapDatabaseViewRowChange *rowChange =
				  (YapDatabaseViewRowChange *)change;
				
				if ([rowChange->originalGroup isEqualToString:group] || [rowChange->finalGroup isEqualToString:group])
				{
					return YES;
				}
			}
		}
	}
	
	return NO;
}

/**
 * A simple YES/NO query to see if any of the given groups within the view changed at all.
**/
- (BOOL)hasChangesForAnyGroups:(NSSet *)groups inNotifications:(NSArray *)notifications
{
	if ([groups count] == 0) return NO;
	
	NSString *registeredName = parent.registeredName;
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:changeset_key_changes];
		
		for (id change in changeset_changes)
		{
			if ([change isKindOfClass:[YapDatabaseViewSectionChange class]])
			{
				__unsafe_unretained YapDatabaseViewSectionChange *sectionChange =
				  (YapDatabaseViewSectionChange *)change;
				
				if ([groups containsObject:sectionChange->group])
				{
					return YES;
				}
			}
			else
			{
				__unsafe_unretained YapDatabaseViewRowChange *rowChange =
				  (YapDatabaseViewRowChange *)change;
				
				if ([groups containsObject:rowChange->originalGroup] || [groups containsObject:rowChange->finalGroup])
				{
					return YES;
				}
			}
		}
	}
	
	return NO;
}

/**
 * This method provides a rough estimate of the size of the change-set.
 * See the header file for more information.
**/
- (NSUInteger)numberOfRawChangesForNotifications:(NSArray *)notifications
{
	NSString *registeredName = parent.registeredName;
	NSUInteger count = 0;
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		  [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:changeset_key_changes];
		
		count += [changeset_changes count];
	}
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setGrouping:(YapDatabaseViewGrouping *)newGrouping
            sorting:(YapDatabaseViewSorting *)newSorting
         versionTag:(NSString *)newVersionTag
{
	grouping = newGrouping;
	groupingChanged = YES;
	
	sorting = newSorting;
	sortingChanged = YES;
	
	versionTag = newVersionTag;
	versionTagChanged = YES;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
{
	if (!grouping || !sorting)
	{
		// Fetch & Cache
		
		__unsafe_unretained YapDatabaseAutoView *view = (YapDatabaseAutoView *)parent;
		
		YapDatabaseViewGrouping *mostRecentGrouping = nil;
		YapDatabaseViewSorting  *mostRecentSorting  = nil;
		
		BOOL needsGrouping = (grouping == nil);
		BOOL needsSorting = (sorting == nil);
		
		[view getGrouping:(needsGrouping ? &mostRecentGrouping : NULL)
		          sorting:(needsSorting  ? &mostRecentSorting  : NULL)];
		
		if (needsGrouping) {
			grouping = mostRecentGrouping;
		}
		if (needsSorting) {
			sorting = mostRecentSorting;
		}
	}
	
	if (groupingPtr) *groupingPtr = grouping;
	if (sortingPtr)  *sortingPtr  = sorting;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
{
	[self getGrouping:groupingPtr
	          sorting:NULL];
}

- (void)getSorting:(YapDatabaseViewSorting **)sortingPtr
{
	[self getGrouping:NULL
	          sorting:sortingPtr];
}

@end
