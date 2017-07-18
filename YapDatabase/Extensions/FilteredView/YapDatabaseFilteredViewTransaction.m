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
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
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
				[self insertRowid:rowid collectionKey:ck
				                              inGroup:group
				                              atIndex:filteredIndex];
				
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
- (void)repopulateViewDueToParentGroupingSortingChange
{
	// Code overview:
	//
	// We could simply run the usual algorithm.
	// That is, enumerate over every item in the database, and run pretty much the same code as
	// in the didUpdateObject:forCollectionKey:withMetadata:rowid:.
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
	
	[self enumerateGroupsUsingBlock:^(NSString *group, BOOL __unused *outerStop) {
		
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL __unused *innerStop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			 
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[parentConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
	}];
	
	isRepopulate = YES;
	{
		[self populateView];
	}
	isRepopulate = NO;
}

/**
 * This method is invoked if:
 *
 * - Our parentView is a filteredView, and its filteringBlock was changed.
 * - A parentView of our parentView is a filteredView, and its filteringBlock was changed.
**/
- (void)repopulateViewDueToParentFilteringChange
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
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
					
					[self insertRowid:rowid collectionKey:ck
					                              inGroup:group
					                              atIndex:index];
					
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
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
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
					
					[self insertRowid:rowid collectionKey:ck
					                              inGroup:group
					                              atIndex:index];
					
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
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * 
 * This method will use parentView to calculate the proper index for the rowid.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
            inGroup:(NSString *)group
        withChanges:(YapDatabaseViewChangesBitMask)flags
              isNew:(BOOL)isGuaranteedNew
{
	YDBLogAutoTrace();
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization.
	
	BOOL tryExistingIndexInGroup = NO;
	
	YapDatabaseViewLocator *existingLocator = isGuaranteedNew ? nil : [self locatorForRowid:rowid];
	if (existingLocator)
	{
		// The key is already in the view.
		// Has it changed groups?
		
		if ([group isEqualToString:existingLocator.group])
		{
			// The key is already in the group.
			//
			// Possible optimization:
			// Object or metadata was updated, but doesn't affect the position of the row within the view.
			
			tryExistingIndexInGroup = YES;
		}
		else
		{
			// The item has changed groups.
			// Remove it from previous group.
			
			[self removeRowid:rowid collectionKey:collectionKey withLocator:existingLocator];
		}
	}
	
	// Is this a new group ?
	// Or the first item in an empty group ?
	
	NSUInteger count = [self numberOfItemsInGroup:group];
	
	if (count == 0)
	{
		// First object added to group.
		
		[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:0];
		return;
	}
	
	// Figure out where the rowid is within the parentView.
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:filteredView->parentViewName];
	
	YapDatabaseViewLocator *locator = [parentViewTransaction locatorForRowid:rowid];
	
	// Optimization:
	//
	// Check the existing position in-case the index didn't change.
	
	if (tryExistingIndexInGroup)
	{
		// Edge case: existing key is the only key in the group
		//
		// (existingIndex == 0) && (count == 1)
		
		NSUInteger existingIndexInGroup = existingLocator.index;
		BOOL useExistingIndexInGroup = YES;
		
		if (existingIndexInGroup > 0)
		{
			NSUInteger prevIndexInGroup = existingIndexInGroup - 1;
			
			int64_t prevRowid = 0;
			[self getRowid:&prevRowid atIndex:prevIndexInGroup inGroup:group];
			
			YapDatabaseViewLocator *prevLocator = [parentViewTransaction locatorForRowid:prevRowid];
			
			useExistingIndexInGroup = (prevLocator.index < locator.index);
		}
		
		if ((existingIndexInGroup + 1) < count && useExistingIndexInGroup)
		{
			NSUInteger nextIndexInGroup = existingIndexInGroup + 1;
			
			int64_t nextRowid = 0;
			[self getRowid:&nextRowid atIndex:nextIndexInGroup inGroup:group];
			
			YapDatabaseViewLocator *nextLocator = [parentViewTransaction locatorForRowid:nextRowid];
			
			useExistingIndexInGroup = (nextLocator.index > locator.index);
		}
		
		if (useExistingIndexInGroup)
		{
			// The item didn't change position.
			
			YDBLogVerbose(@"Updated key(%@) in group(%@) maintains current index", collectionKey.key, group);
			
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:group
			                                        atIndex:existingIndexInGroup
			                                    withChanges:flags]];
			return;
		}
		else
		{
			// The item has changed position within its group.
			// Remove it from previous position (and don't forget to decrement count).
			
			[self removeRowid:rowid collectionKey:collectionKey withLocator:existingLocator];
			count--;
		}
	}
	
	// Calculate where the rowid should go
	// We do this by searching the parentView for a rowid that's in our filtered list.
	//
	// Algorithm:
	// - start with the rowids immediately (index-1, index+1) next to the rowid in the parentView
	// - look for those rowids in our list
	// - if found, we know where to place the rowid within our filtered list
	// - otherwise try the rowids further out (index-2, index+2) until we find a match
	
	NSUInteger offset = 1;
	
	NSUInteger parentIndex = locator.index;
	NSUInteger parentCount = [parentViewTransaction numberOfItemsInGroup:group];
	
	NSUInteger index = 0;
	do {
		
		if (parentIndex >= offset)
		{
			NSUInteger prevIndex = parentIndex - offset;
			
			int64_t prevRowid = 0;
			[parentViewTransaction getRowid:&prevRowid atIndex:prevIndex inGroup:group];
			
			YapDatabaseViewLocator *prevLocator = [self locatorForRowid:prevRowid];
			if (prevLocator)
			{
				index = prevLocator.index + 1;
				break;
			}
		}
		
		if ((parentIndex + offset) < parentCount)
		{
			NSUInteger nextIndex = parentIndex + offset;
			
			int64_t nextRowid = 0;
			[parentViewTransaction getRowid:&nextRowid atIndex:nextIndex inGroup:group];
			
			YapDatabaseViewLocator *nextLocator = [self locatorForRowid:nextRowid];
			if (nextLocator)
			{
				index = nextLocator.index;
				break;
			}
		}
		
		offset++;
		
	} while (YES);
	
	[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:index];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_didChangeWithRowid:(int64_t)rowid
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
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = filteredView->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
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
		
		if ([self containsRowid:rowid])
		{
			passesFilter = YES;
		}
	}
	
	if (passesFilter)
	{
		// Add row to view (or update position).
		
		[self insertRowid:rowid
			 collectionKey:collectionKey
		          inGroup:group
		      withChanges:changesBitMask
		            isNew:isInsert];
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
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeOnInsertOnly;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	[self _didChangeWithRowid:rowid
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
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	[self _didChangeWithRowid:rowid
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
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	BOOL filteringNeedsMetadata = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if (filteringMayHaveChanged && filteringNeedsMetadata)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
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
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	BOOL filteringNeedsObject    = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if (filteringMayHaveChanged && filteringNeedsObject)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
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
- (void)didTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	BOOL filteringNeedsObject    = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsMetadata  = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if (filteringMayHaveChanged && filteringNeedsObject)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (filteringMayHaveChanged && filteringNeedsMetadata)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
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
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	BOOL filteringNeedsObject    = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsMetadata  = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if (filteringMayHaveChanged && filteringNeedsObject)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (filteringMayHaveChanged && filteringNeedsMetadata)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
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
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredViewConnection *filteredViewConnection =
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask =
	  YapDatabaseBlockInvokeIfObjectTouched | YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewFiltering *filtering = nil;
	[filteredViewConnection getFiltering:&filtering];
	
	// Note: Until we can check every parentView in the stack below us,
	// we have to assume that grouping and/or sorting may have changed.
	
	BOOL filteringMayHaveChanged = (filtering->blockInvokeOptions & blockInvokeBitMask);
	BOOL filteringNeedsObject    = (filtering->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL filteringNeedsMetadata  = (filtering->blockType & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if (filteringMayHaveChanged && filteringNeedsObject)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (filteringMayHaveChanged && filteringNeedsMetadata)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _didChangeWithRowid:rowid
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
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collectionKey.collection])
	{
		return;
	}
	
	// Process as usual
	
	[self removeRowid:rowid collectionKey:collectionKey];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	// Should we ignore the rows based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Process as usual
	
	NSMutableDictionary *collectionKeys = [NSMutableDictionary dictionaryWithCapacity:keys.count];
	
	[rowids enumerateObjectsUsingBlock:^(NSNumber *rowidNumber, NSUInteger idx, BOOL *stop) {
		
		NSString *key = [keys objectAtIndex:idx];
		
		collectionKeys[rowidNumber] = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	}];
	
	NSDictionary *locators = [self locatorsForRowids:rowids];
	
	[self removeRowidsWithCollectionKeys:collectionKeys locators:locators];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllRowids];
}

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
	  (YapDatabaseFilteredView *)parentConnection->parent;
	
	if (![parentViewName isEqualToString:filteredView->parentViewName])
	{
		YDBLogWarn(@"%@ - Method inappropriately invoked. Doesn't match parentViewName.", THIS_METHOD);
		return;
	}
	
	// The parentView has significantly changed.
	// We need to repopulate.
	
	BOOL groupingMayHaveChanged = (flags & YDB_GroupingMayHaveChanged) ? YES : NO;
	BOOL sortingMayHaveChanged  = (flags & YDB_SortingMayHaveChanged) ? YES : NO;
	
	if (groupingMayHaveChanged || sortingMayHaveChanged)
	{
		[self repopulateViewDueToParentGroupingSortingChange];
	}
	else
	{
		[self repopulateViewDueToParentFilteringChange];
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
	  (YapDatabaseFilteredViewConnection *)parentConnection;
	
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
				int flags = YDB_FilteringMayHaveChanged;
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
}

@end
