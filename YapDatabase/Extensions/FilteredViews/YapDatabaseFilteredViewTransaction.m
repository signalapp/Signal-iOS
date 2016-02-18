#import "YapDatabaseFilteredViewTransaction.h"
#import "YapDatabaseFilteredViewPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapCollectionKey.h"
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


@implementation YapDatabaseFilteredViewTransaction

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to create any necessary tables (if needed),
 * as well as populate the view (if needed) by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{
	YDBLogAutoTrace();
	
	if (![self isPersistentView])
	{
		// We're registering an In-Memory-Only View (non-persistent) (not stored in the database).
		// So we can skip all the checks because we know we need to create the memory tables.
		
		if (![self createTables]) return NO;
		
		if (!viewConnection->view->options.skipInitialViewPopulation)
		{
			if (![self populateView]) return NO;
		}
		
		// Store initial versionTag in prefs table
		
		NSString *versionTag = [viewConnection->view versionTag]; // MUST get init value from view
		
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:NO];
		
		// If there was a previously registered persistent view with this name,
		// then we should drop those tables from the database.
		
		BOOL dropPersistentTables = [self getIntValue:NULL forExtensionKey:ext_key_classVersion persistent:YES];
		if (dropPersistentTables)
		{
			[[viewConnection->view class]
			  dropTablesForRegisteredName:[self registeredName]
			              withTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
			                wasPersistent:YES];
		}
		
		return YES;
	}
	else
	{
		// We're registering a Peristent View (stored in the database).
		
		__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)(viewConnection->view);
		
		int classVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
		
		NSString *parentViewName = filteredView->parentViewName;
		NSString *versionTag = [viewConnection->view versionTag]; // MUST get init value from view
		
		// Figure out what steps we need to take in order to register the view
		
		BOOL needsCreateTables = NO;
		BOOL needsPopulateView = NO;
		
		// Check classVersion (the internal version number of view implementation)
		
		int oldClassVersion = 0;
		BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion
		                            forExtensionKey:ext_key_classVersion persistent:YES];
		
		if (!hasOldClassVersion)
		{
			// First time registration
			
			needsCreateTables = YES;
			needsPopulateView = !viewConnection->view->options.skipInitialViewPopulation;
		}
		else if (oldClassVersion != classVersion)
		{
			// Upgrading from older codebase
			
			[self dropTablesForOldClassVersion:oldClassVersion];
			needsCreateTables = YES;
			needsPopulateView = YES; // Not initialViewPopulation, but rather codebase upgrade.
		}
		
		// Create the database tables (if needed)
		
		if (needsCreateTables)
		{
			if (![self createTables]) return NO;
		}
		
		// Check other variables (if needed)
		
		NSString *oldParentViewName = nil;
		NSString *oldVersionTag = nil;
		NSString *oldTag_deprecated = nil;
		
		if (!hasOldClassVersion)
		{
			// If there wasn't a classVersion in the table,
			// then there won't be other values either.
		}
		else
		{
			// Check parentViewName.
			// Need to re-populate if the parent changed.
			
			oldParentViewName = [self stringValueForExtensionKey:ext_key_parentViewName persistent:YES];
			
			if (![oldParentViewName isEqualToString:parentViewName])
			{
				needsPopulateView = YES;  // Not initialViewPopulation, but rather config change.
			}
			
			// Check user-supplied tag.
			// We may need to re-populate the database if the groupingBlock or sortingBlock changed.
			
			oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
			
			if (oldVersionTag == nil)
			{
				oldTag_deprecated = [self stringValueForExtensionKey:ext_key_tag_deprecated persistent:YES];
				if (oldTag_deprecated)
				{
					oldVersionTag = oldTag_deprecated;
				}
			}
			
			if (![oldVersionTag isEqualToString:versionTag])
			{
				needsPopulateView = YES; // Not initialViewPopulation, but rather versionTag upgrade.
			}
		}
		
		// Repopulate table (if needed)
		
		if (needsPopulateView)
		{
			if (![self populateView]) return NO;
		}
		
		// Update yap2 table values (if needed)
		
		if (!hasOldClassVersion || (oldClassVersion != classVersion)) {
			[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		}
		
		if (![oldParentViewName isEqualToString:parentViewName]) {
			[self setStringValue:parentViewName forExtensionKey:ext_key_parentViewName persistent:YES];
		}
		
		if (oldTag_deprecated)
		{
			[self removeValueForExtensionKey:ext_key_tag_deprecated persistent:YES];
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		}
		else if (![oldVersionTag isEqualToString:versionTag])
		{
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		}
	
		return YES;
	}
}

/**
 * Internal method.
 * This method overrides the version in YapDatabaseViewTransaction.
 *
 * This method is called, if needed, to populate the view.
 * It does so by enumerating the rows in the database, and invoking the usual blocks and insertion methods.
**/
- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Initialize ivars (if needed)
	
	if (viewConnection->state == nil)
		viewConnection->state = [[YapDatabaseViewState alloc] init];
	
	// Setup the block to properly invoke the filterBlock.
	
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getFiltering:&filtering];
	
	BOOL (^InvokeFilterBlock)(NSString *group, int64_t rowid, YapCollectionKey *ck);
	
	if (filtering->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t __unused rowid, YapCollectionKey *ck){
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, metadata);
		};
	}
	else // if (filtering->blockType == YapDatabaseBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = nil;
			id metadata = nil;
			[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object, metadata);
		};
	}
	
	// Enumerate the existing rows in the database and populate the view
	
	for (NSString *group in [parentViewTransaction allGroups])
	{
		__block NSUInteger filteredIndex = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger __unused parentIndex, BOOL __unused *stop)
		{
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
			
			if (InvokeFilterBlock(group, rowid, ck))
			{
				if (filteredIndex == 0) {
					[self insertRowid:rowid collectionKey:ck inNewGroup:group];
				}
				else {
					[self insertRowid:rowid collectionKey:ck
					                              inGroup:group
					                              atIndex:filteredIndex
					                  withExistingPageKey:nil];
				}
				filteredIndex++;
			}
		}];
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Repopulate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked if:
 *
 * - Our parentView had its groupingBlock and/or sortingBlock changed.
 * - A parentView of our parentView had its groupingBlock and/or sortingBlock changed.
**/
- (void)repopulateViewDueToParentGroupingBlockChange
{
	// Update our groupingBlock & sortingBlock to match the changed parent
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	__unsafe_unretained YapDatabaseViewConnection *parentViewConnection = parentViewTransaction->viewConnection;
	
	YapDatabaseViewGrouping *newGrouping;
	YapDatabaseViewSorting  *newSorting;
	
	[parentViewConnection getGrouping:&newGrouping
	                          sorting:&newSorting];
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	[filteredViewConnection setGrouping:newGrouping
	                            sorting:newSorting];
	
	// Code overview:
	//
	// We could simply run the usual algorithm.
	// That is, enumerate over every item in the database, and run pretty much the same code as
	// in the handleUpdateObject:forCollectionKey:withMetadata:rowid:.
	// However, this causes a potential issue where the sortingBlock will be invoked with items that
	// no longer exist in the given group.
	//
	// Instead we're going to find a way around this.
	// That way the sortingBlock works in a manner we're used to.
	//
	// Here's the algorithm overview:
	//
	// - Insert remove ops for every row & group
	// - Remove all items from the database tables
	// - Flush the group_pagesMetadata_dict (and related ivars)
	// - Set the reset flag (for internal notification creation)
	// - And then run the normal populate routine, with one exceptione handled by the isRepopulate flag.
	//
	// The changeset mechanism will automatically consolidate all changes to the minimum.
	
	[viewConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL __unused *outerStop) {
		
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL __unused *innerStop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			 
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[viewConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
	}];
	
	isRepopulate = YES;
	[self populateView];
	isRepopulate = NO;
}

/**
 * This method is invoked if:
 *
 * - Our parentView is a filteredView, and its filteringBlock was changed.
 * - A parentView of our parentView is a filteredView, and its filteringBlock was changed.
**/
- (void)repopulateViewDueToParentFilteringBlockChange
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	// The parentView is a filteredView, and its filteringBlock changed
	//
	// - in the parentView, the groups may have changed
	// - in the parentView, the items within each group may have changed
	// - in the parentView, the order of items within each group is the same (important!)
	//
	// So we can run an algorithm similar to 'repopulateViewDueToFilteringBlockChange',
	// but we have to watch out for stuff in our view that no longer exists in the parent view.
	
	// Setup the block to properly invoke the filterBlock.
	
	YapDatabaseViewFiltering *filtering;
	
	[filteredViewConnection getFiltering:&filtering];
	
	BOOL (^InvokeFilterBlock)(NSString *group, int64_t rowid, YapCollectionKey *ck);
	
	if (filtering->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t __unused rowid, YapCollectionKey *ck){
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, metadata);
		};
	}
	else // if (filtering->blockType == YapDatabaseBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = nil;
			id metadata = nil;
			[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object, metadata);
		};
	}
	
	// Start the algorithm.
	
	NSMutableArray *groupsInSelf = [[self allGroups] mutableCopy];
	NSArray *groupsInParent = [parentViewTransaction allGroups];
	
	for (NSString *group in groupsInParent)
	{
		__block BOOL existing = NO;
		__block BOOL existingKnownValid = NO;
		__block int64_t existingRowid = 0;
		
		existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
		
		__block NSUInteger index = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger __unused parentIndex, BOOL __unused *stop)
		{
			if (existing && ((existingRowid == rowid)))
			{
				// Shortcut #1
				//
				// The row was previously in the view (allowed by previous parentFilter + our filter),
				// and is still in the view (allowed by new parentFilter + our filter).
				
				index++;
				existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				existingKnownValid = NO;
				
				return; // from block (continue)
			}
			
			if (existing && !existingKnownValid)
			{
				// Is the existingRowid still contained within the parentView?
				do
				{
					if ([parentViewTransaction containsRowid:existingRowid])
					{
						// Yes it is
						existingKnownValid = YES;
					}
					else
					{
						// No it's not.
						// Remove it, and check the next rowid in the list.
						
						YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:existingRowid];
						[self removeRowid:existingRowid collectionKey:ck atIndex:index inGroup:group];
						
						existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
					}
					
				} while (existing && !existingKnownValid);
					
				if (existing && (existingRowid == rowid))
				{
					// Shortcut #2
					//
					// The row was previously in the view (allowed by previous parentFilter + our filter),
					// and is still in the view (allowed by new parentFilter + our filter).
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
					existingKnownValid = NO;
					
					return; // from block (continue)
				}
			}
			
			{ // otherwise
				
				// The row was not previously in our view.
				// This could be because it was just inserted into the parentView,
				// or because our filter blocked it.
				//
				// Either way we have to check.
			
				YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
				
				if (InvokeFilterBlock(group, rowid, ck))
				{
					// The row was not previously in our view (not previously in parent view),
					// but is now in the view (added to parent view, and allowed by our filter).
				
					if (index == 0 && ([viewConnection->state pagesMetadataForGroup:group] == nil)) {
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					}
					else {
						[self insertRowid:rowid collectionKey:ck
						                              inGroup:group
						                              atIndex:index
					  	                  withExistingPageKey:nil];
					}
					index++;
				}
				else
				{
					// The row was not previously in our view (filtered, or not previously in parent view),
					// and is still not in our view (filtered).
				}
			}
		}];
		
		while (existing)
		{
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:existingRowid];
			[self removeRowid:existingRowid collectionKey:ck atIndex:index inGroup:group];
			
			existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
		}
		
		NSUInteger groupIndex = [groupsInSelf indexOfObject:group];
		if (groupIndex != NSNotFound)
		{
			[groupsInSelf removeObjectAtIndex:groupIndex];
		}
	}
	
	// Check to see if there are any groups that have been completely removed.
	
	for (NSString *group in groupsInSelf)
	{
		[self removeAllRowidsInGroup:group];
	}
}

/**
 * This method is invoked if:
 *
 * - The filteringBlock of this instance is changed
**/
- (void)repopulateViewDueToFilteringBlockChange
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	// The parentView didn't change. And thus:
	// - in the parentView, the groups are the same
	// - in the parentView, the items within each group are the same
	// - in the parentView, the order of items within each group is the same
	
	// Setup the block to properly invoke the filterBlock.
	
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getFiltering:&filtering];
	
	BOOL (^InvokeFilterBlock)(NSString *group, int64_t rowid, YapCollectionKey *ck);
	
	if (filtering->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t __unused rowid, YapCollectionKey *ck){
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object);
		};
	}
	else if (filtering->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, metadata);
		};
	}
	else // if (filteringBlockType == YapDatabaseBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filtering->block;
		
		InvokeFilterBlock = ^(NSString *group, int64_t rowid, YapCollectionKey *ck){
			
			id object = nil;
			id metadata = nil;
			[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
			return filterBlock(databaseTransaction, group, ck.collection, ck.key, object, metadata);
		};
	}
	
	// Start the algorithm.
	
	for (NSString *group in [parentViewTransaction allGroups])
	{
		__block BOOL existing = NO;
		__block int64_t existingRowid = 0;
		
		existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
		
		__block NSUInteger index = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger __unused parentIndex, BOOL __unused *stop)
		{
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
			
			if (InvokeFilterBlock(group, rowid, ck))
			{
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (allowed by previous filter),
					// and is still in the view (allowed by new filter).
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (disallowed by previous filter),
					// but is now in the view (allowed by new filter).
					
					if (index == 0 && ([viewConnection->state pagesMetadataForGroup:group] == nil)) {
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					}
					else {
						[self insertRowid:rowid collectionKey:ck inGroup:group
						                                         atIndex:index withExistingPageKey:nil];
					}
					index++;
				}
			}
			else
			{
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (allowed by previous filter),
					// but is no longer in the view (disallowed by new filter).
					
					[self removeRowid:rowid collectionKey:ck atIndex:index inGroup:group];
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (disallowed by previous filter),
					// and is still not in the view (disallowed by new filter).
				}
			}
		}];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
                        object:(id)object
                      metadata:(id)metadata
                     filtering:(YapDatabaseViewFiltering *)filtering
            blockInvokeBitMask:(YapDatabaseBlockInvoke)blockInvokeBitMask
                changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	// Since our groupingBlock is the same as the parent's groupingBlock,
	// just ask the parentViewTransaction for the group (which is cached info).
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = [parentViewTransaction groupForRowid:rowid];
	
	if (group == nil)
	{
		// Not included in parentView.
		// Remove key from view (if needed).
		
		if (!isInsert)
		{
			[self removeRowid:rowid collectionKey:collectionKey];
		}
		
		return;
	}
	
	// Determine if the filtering may have changed
	
	BOOL filteringMayHaveChanged;
	if (isInsert)
		filteringMayHaveChanged = YES;
	else
		filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL passesFilter = NO;
	
	if (filteringMayHaveChanged)
	{
		// Ask filter block if we should add key to view.
		
		if (filtering->blockType == YapDatabaseBlockTypeWithKey)
		{
			YapDatabaseViewFilteringWithKeyBlock filterBlock =
			  (YapDatabaseViewFilteringWithKeyBlock)filtering->block;
			
			passesFilter = filterBlock(databaseTransaction, group, collection, key);
		}
		else if (filtering->blockType == YapDatabaseBlockTypeWithObject)
		{
			YapDatabaseViewFilteringWithObjectBlock filterBlock =
			  (YapDatabaseViewFilteringWithObjectBlock)filtering->block;
			
			passesFilter = filterBlock(databaseTransaction, group, collection, key, object);
		}
		else if (filtering->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			YapDatabaseViewFilteringWithMetadataBlock filterBlock =
			  (YapDatabaseViewFilteringWithMetadataBlock)filtering->block;
			
			passesFilter = filterBlock(databaseTransaction, group, collection, key, metadata);
		}
		else // if (filtering->blockType == YapDatabaseBlockTypeWithRow)
		{
			YapDatabaseViewFilteringWithRowBlock filterBlock =
			  (YapDatabaseViewFilteringWithRowBlock)filtering->block;
			
			passesFilter = filterBlock(databaseTransaction, group, collection, key, object, metadata);
		}
	}
	else
	{
		// The filteringBlock doesn't need to be run.
		// So 'passesFilter' is the same as last time.
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		if (pageKey)
		{
			passesFilter = YES;
		}
	}
	
	if (passesFilter)
	{
		// Add row to view (or update position).
		
		[self insertRowid:rowid
			collectionKey:collectionKey
				   object:object
				 metadata:metadata
				  inGroup:group
			  withChanges:changesBitMask
					isNew:NO];
	}
	else
	{
		// Filtered from this view.
		// Remove row from view (if needed).
		
		if (!isInsert)
		{
			[self removeRowid:rowid collectionKey:collectionKey];
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeOnInsertOnly;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:YES];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewSorting   *sorting   = nil;
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getGrouping:NULL
	                            sorting:&sorting
	                          filtering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL sortingNeedsMetadata   = (sorting->blockType   & YapDatabaseBlockType_MetadataFlag);
	BOOL filteringNeedsMetadata = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if (sortingNeedsMetadata || (filteringMayHaveChanged && filteringNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewSorting   *sorting   = nil;
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getGrouping:NULL
	                            sorting:&sorting
	                          filtering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL sortingNeedsObject   = (sorting->blockType   & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsObject = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if (sortingNeedsObject || (filteringMayHaveChanged && filteringNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewSorting   *sorting   = nil;
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getGrouping:NULL
	                            sorting:&sorting
	                          filtering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL sortingNeedsObject   = (sorting->blockType   & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsObject = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if (sortingNeedsObject || (filteringMayHaveChanged && filteringNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	BOOL sortingNeedsMetadata   = (sorting->blockType   & YapDatabaseBlockType_MetadataFlag);
	BOOL filteringNeedsMetadata = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if (sortingNeedsMetadata || (filteringMayHaveChanged && filteringNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewSorting   *sorting   = nil;
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getGrouping:NULL
	                            sorting:&sorting
	                          filtering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL sortingNeedsObject   = (sorting->blockType   & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsObject = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if (sortingNeedsObject || (filteringMayHaveChanged && filteringNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	BOOL sortingNeedsMetadata   = (sorting->blockType   & YapDatabaseBlockType_MetadataFlag);
	BOOL filteringNeedsMetadata = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if (sortingNeedsMetadata || (filteringMayHaveChanged && filteringNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)handleTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask =
	  YapDatabaseBlockInvokeIfObjectTouched | YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewSorting   *sorting   = nil;
	YapDatabaseViewFiltering *filtering = nil;
	
	[filteredViewConnection getGrouping:NULL
	                            sorting:&sorting
	                          filtering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	
	BOOL sortingNeedsObject   = (sorting->blockType   & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsObject = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if (sortingNeedsObject || (filteringMayHaveChanged && filteringNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	BOOL sortingNeedsMetadata   = (sorting->blockType   & YapDatabaseBlockType_MetadataFlag);
	BOOL filteringNeedsMetadata = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if (sortingNeedsMetadata || (filteringMayHaveChanged && filteringNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                   filtering:filtering
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

///
/// All other hook methods are handled by superclass (YapDatabaseViewTransaction).
///

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseViewDependency Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked if our parentView repopulates.
 * For example:
 *
 * - The parentView is a YapDatabaseView, and the groupingBlock and/or sortingBlock was changed.
 * - The parentView is a YapDatabaseFilteredView, and the filterBlock was changed.
 * - The parentView of the parentView was changed...
 * 
 * When this happens, there has likely been a significant change in the content of the parentView,
 * and a full repopulate is required on our part.
**/
- (void)view:(NSString *)parentViewName didRepopulateWithFlags:(int)flags
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	if (![parentViewName isEqualToString:filteredView->parentViewName])
	{
		YDBLogWarn(@"%@ - Method inappropriately invoked. Doesn't match parentViewName.", THIS_METHOD);
		return;
	}
	
	// The parentView has significantly changed.
	// We need to repopulate.
	
	BOOL groupingBlockChanged = (flags & YDB_GroupingBlockChanged) ? YES : NO;
	BOOL sortingBlockChanged = (flags & YDB_SortingBlockChanged) ? YES : NO;
	
	if (groupingBlockChanged || sortingBlockChanged)
	{
		[self repopulateViewDueToParentGroupingBlockChange];
	}
	else
	{
		[self repopulateViewDueToParentFilteringBlockChange];
	}
	
	// Propogate the notification onward to any extensions dependent upon this one.
	
	__unsafe_unretained NSString *registeredName = [self registeredName];
	__unsafe_unretained NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(view:didRepopulateWithFlags:)])
			{
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseFilteredViewTransaction (ReadWrite)

- (void)setGrouping:(YapDatabaseViewGrouping __unused *)grouping
            sorting:(YapDatabaseViewSorting __unused *)sorting
         versionTag:(NSString __unused *)versionTag
{
	NSString *reason = @"This method is not available for YapDatabaseFilteredView.";
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	  @"YapDatabaseFilteredView is designed to filter an existing YapDatabaseView instance."
	  @" You may update the filteringBlock, or you may invoke this method on the parent YapDatabaseView."};
	
	@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
}

- (void)setFiltering:(YapDatabaseViewFiltering *)filtering
          versionTag:(NSString *)inVersionTag

{
	YDBLogAutoTrace();
	
	NSAssert(filtering != nil, @"Invalid parameter: filtering == nil");
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	NSString *newVersionTag = inVersionTag ? [inVersionTag copy] : @"";
	
	if ([[self versionTag] isEqualToString:newVersionTag])
	{
		YDBLogWarn(@"%@ - versionTag didn't change, so not updating view", THIS_METHOD);
		return;
	}
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)viewConnection;
	
	[filteredViewConnection setFiltering:filtering
	                          versionTag:newVersionTag];
	
	[self repopulateViewDueToFilteringBlockChange];
	
	[self setStringValue:newVersionTag
	     forExtensionKey:ext_key_versionTag
	          persistent:[self isPersistentView]];
	
	// Notify any extensions dependent upon this one that we repopulated.
	
	NSString *registeredName = [self registeredName];
	NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(view:didRepopulateWithFlags:)])
			{
				int flags = YDB_FilteringBlockChanged;
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
}

@end
