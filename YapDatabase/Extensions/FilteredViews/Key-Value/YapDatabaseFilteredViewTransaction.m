#import "YapDatabaseFilteredViewTransaction.h"
#import "YapDatabaseFilteredViewPrivate.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabasePrivate.h"
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


@implementation YapDatabaseFilteredViewTransaction

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
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:filteredView->parentViewName];
	__unsafe_unretained YapDatabaseView *parentView = parentViewTransaction->viewConnection->view;
	
	// Capture grouping & sorting block
	
	filteredView->groupingBlock = parentView->groupingBlock;
	filteredView->groupingBlockType = parentView->groupingBlockType;
	
	filteredView->sortingBlock = parentView->sortingBlock;
	filteredView->sortingBlockType = parentView->sortingBlockType;
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Initialize ivars
	
	viewConnection->group_pagesMetadata_dict = [[NSMutableDictionary alloc] init];
	viewConnection->pageKey_group_dict = [[NSMutableDictionary alloc] init];
	
	// Enumerate the existing rows in the database and populate the view
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop) {
				
				NSString *key = nil;
				[databaseTransaction getKey:&key forRowid:rowid];
				
				if (filterBlock(group, key))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid key:key inNewGroup:group];
					else
						[self insertRowid:rowid key:key inGroup:group atIndex:filteredIndex withExistingPageKey:nil];
					
					filteredIndex++;
				}
			}];
		}
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop) {
												   
				NSString *key = nil;
				id object = nil;
				[databaseTransaction getKey:&key object:&object forRowid:rowid];
				
				if (filterBlock(group, key, object))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid key:key inNewGroup:group];
					else
						[self insertRowid:rowid key:key inGroup:group atIndex:filteredIndex withExistingPageKey:nil];
					
					filteredIndex++;
				}
			}];
		}
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop) {
												   
				NSString *key = nil;
				id metadata = nil;
				[databaseTransaction getKey:&key metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, key, metadata))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid key:key inNewGroup:group];
					else
						[self insertRowid:rowid key:key inGroup:group atIndex:filteredIndex withExistingPageKey:nil];
					
					filteredIndex++;
				}
			}];
		}
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop) {
												   
				NSString *key = nil;
				id object = nil;
				id metadata = nil;
				[databaseTransaction getKey:&key object:&object metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, key, object, metadata))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid key:key inNewGroup:group];
					else
						[self insertRowid:rowid key:key inGroup:group atIndex:filteredIndex withExistingPageKey:nil];
					
					filteredIndex++;
				}
			}];
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseExtensionTransaction_KeyValue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)viewConnection->view;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = parentViewTransaction->lastHandledGroup;
	
	if (group == nil)
	{
		// Not included in parentView.
		// This was an insert operation, so we know the key wasn't already in the view.
		
		lastHandledGroup = nil;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// This was an insert operation, so we know the key wasn't already in the view.
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid key:key object:object metadata:metadata inGroup:group withChanges:flags isNew:YES];
		lastHandledGroup = group;
	}
	else
	{
		// Filtered from this view.
		// This was an insert operation, so we know the key wasn't already in the view.
		
		lastHandledGroup = nil;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)viewConnection->view;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = parentViewTransaction->lastHandledGroup;
	
	if (group == nil)
	{
		// Not included in parentView.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid key:key];
		
		lastHandledGroup = nil;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid key:key object:object metadata:metadata inGroup:group withChanges:flags isNew:NO];
		lastHandledGroup = group;
	}
	else
	{
		// Filtered from this view.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid key:key];
		lastHandledGroup = nil;
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateMetadata:(id)metadata forKey:(NSString *)key withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)viewConnection->view;
	
	BOOL groupMayHaveChanged = filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                           filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata;
	
	BOOL sortMayHaveChanged = filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                          filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = parentViewTransaction->lastHandledGroup;
	
	if (group == nil)
	{
		// Not included in parentView.
		
		if (groupMayHaveChanged)
		{
			// Remove key from view (if needed).
			// This was an update operation, so the key may have previously been in the view.
			
			[self removeRowid:rowid key:key];
		}
		else
		{
			// The group hasn't changed.
			// Thus it wasn't previously in view, and still isn't in the view.
		}
		
		lastHandledGroup = nil;
		return;
	}
	
	BOOL filterMayHaveChanged = filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow ||
	                            filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata;
	
	if (!groupMayHaveChanged && !sortMayHaveChanged && !filterMayHaveChanged)
	{
		// Nothing has changed that could possibly affect the view.
		// Just note the touch.
		
		int flags = YapDatabaseViewChangedMetadata;
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
		
		[viewConnection->changes addObject:
		    [YapDatabaseViewRowChange updateKey:key changes:flags inGroup:group atIndex:existingIndex]];
		
		lastHandledGroup = group;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	id object = nil;
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		object = [databaseTransaction objectForKey:key withRowid:rowid];
		passesFilter = filterBlock(group, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		object = [databaseTransaction objectForKey:key withRowid:rowid];
		passesFilter = filterBlock(group, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		BOOL sortingBlockNeedsObject = sortMayHaveChanged; // same thing, different name
		if (sortingBlockNeedsObject && object == nil)
		{
			object = [databaseTransaction objectForKey:key withRowid:rowid];
		}
		
		[self insertRowid:rowid key:key object:object metadata:metadata inGroup:group withChanges:flags isNew:NO];
		lastHandledGroup = group;
	}
	else
	{
		// Filtered from this view.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid key:key];
		lastHandledGroup = nil;
	}
}

///
/// All other hook methods are handled by superclass (YapDatabaseViewTransaction).
///

@end
