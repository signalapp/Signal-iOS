#import "YapCollectionsDatabaseFilteredViewTransaction.h"
#import "YapCollectionsDatabaseFilteredViewPrivate.h"
#import "YapCollectionsDatabasePrivate.h"
#import "YapDatabaseViewChangePrivate.h"
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


@implementation YapCollectionsDatabaseFilteredViewTransaction

/**
 * Internal method.
 * This method overrides the version in YapCollectionsDatabaseViewTransaction.
 *
 * This method is called, if needed, to populate the view.
 * It does so by enumerating the rows in the database, and invoking the usual blocks and insertion methods.
**/
- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseFilteredView *filteredView =
	  (YapCollectionsDatabaseFilteredView *)viewConnection->view;
	
	YapCollectionsDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	__unsafe_unretained YapCollectionsDatabaseView *parentView = parentViewTransaction->viewConnection->view;
	
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
	
	if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
	{
		YapCollectionsDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				[databaseTransaction getKey:&key collection:&collection forRowid:rowid];
				
				if (filterBlock(group, collection, key))
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:collectionKey inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:filteredIndex
						                                                      withExistingPageKey:nil];
					filteredIndex++;
				}
			}];
		}
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		YapCollectionsDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				id object = nil;
				[databaseTransaction getKey:&key collection:&collection object:&object forRowid:rowid];
				
				if (filterBlock(group, collection, key, object))
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:collectionKey inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:filteredIndex
						                                                      withExistingPageKey:nil];
					filteredIndex++;
				}
			}];
		}
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
	{
		YapCollectionsDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				id metadata = nil;
				[databaseTransaction getKey:&key collection:&collection metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, collection, key, metadata))
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:collectionKey inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:filteredIndex
						                                                      withExistingPageKey:nil];
					filteredIndex++;
				}
			}];
		}
	}
	else // if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow)
	{
		YapCollectionsDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block NSUInteger filteredIndex = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				id object = nil;
				id metadata = nil;
				
				[databaseTransaction getKey:&key
				                 collection:&collection
				                     object:&object
				                   metadata:&metadata
				                   forRowid:rowid];
				
				if (filterBlock(group, collection, key, object, metadata))
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:collectionKey inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:filteredIndex
						                                                      withExistingPageKey:nil];
					filteredIndex++;
				}
			}];
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapAbstractDatabaseExtensionTransaction_CollectionKeyValue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapCollectionsDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapCollectionsDatabaseFilteredView *filteredView =
	  (YapCollectionsDatabaseFilteredView *)viewConnection->view;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapCollectionsDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
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
	
	if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
	{
		YapCollectionsDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		YapCollectionsDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
	{
		YapCollectionsDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow)
	{
		YapCollectionsDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// This was an insert operation, so we know the key wasn't already in the view.
		
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:YES];
		
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
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapCollectionsDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	NSParameterAssert(key != nil);
	NSParameterAssert(collection != nil);
	
	__unsafe_unretained YapCollectionsDatabaseFilteredView *filteredView =
	  (YapCollectionsDatabaseFilteredView *)viewConnection->view;
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapCollectionsDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = parentViewTransaction->lastHandledGroup;
	
	if (group == nil)
	{
		// Not included in parentView.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
		
		lastHandledGroup = nil;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	
	if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
	{
		YapCollectionsDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		YapCollectionsDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
	{
		YapCollectionsDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow)
	{
		YapCollectionsDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:NO];
		
		lastHandledGroup = group;
	}
	else
	{
		// Filtered from this view.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
		lastHandledGroup = nil;
	}
}

/**
 * YapCollectionsDatabase extension hook.
 * This method is invoked by a YapCollectionsDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapCollectionsDatabaseViewTransaction.
**/
- (void)handleUpdateMetadata:(id)metadata
                      forKey:(NSString *)key
                inCollection:(NSString *)collection
                   withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	NSParameterAssert(key != nil);
	NSParameterAssert(collection != nil);
	
	__unsafe_unretained YapCollectionsDatabaseFilteredView *filteredView =
	  (YapCollectionsDatabaseFilteredView *)viewConnection->view;
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	BOOL groupMayHaveChanged = filteredView->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithRow ||
	                           filteredView->groupingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata;
	
	BOOL sortMayHaveChanged = filteredView->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithRow ||
	                          filteredView->sortingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapCollectionsDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	NSString *group = parentViewTransaction->lastHandledGroup;
	
	if (group == nil)
	{
		// Not included in parentView.
		
		if (groupMayHaveChanged)
		{
			// Remove key from view (if needed).
			// This was an update operation, so the key may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
		}
		else
		{
			// The group hasn't changed.
			// Thus it wasn't previously in view, and still isn't in the view.
		}
		
		lastHandledGroup = nil;
		return;
	}
	
	BOOL filterMayHaveChanged = filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow ||
	                            filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata;
	
	if (!groupMayHaveChanged && !sortMayHaveChanged && !filterMayHaveChanged)
	{
		// Nothing has changed that could possibly affect the view.
		// Just note the touch.
		
		int flags = YapDatabaseViewChangedMetadata;
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
		
		[viewConnection->changes addObject:
		    [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
		
		lastHandledGroup = group;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	id object = nil;
	
	if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithKey)
	{
		YapCollectionsDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithObject)
	{
		YapCollectionsDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata)
	{
		YapCollectionsDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow)
	{
		YapCollectionsDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapCollectionsDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		BOOL sortingBlockNeedsObject = sortMayHaveChanged; // same thing, different name
		if (sortingBlockNeedsObject && object == nil)
		{
			object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
		}
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:NO];
		
		lastHandledGroup = group;
	}
	else
	{
		// Filtered from this view.
		// Remove key from view (if needed).
		// This was an update operation, so the key may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
		lastHandledGroup = nil;
	}
}

///
/// All other hook methods are handled by superclass (YapDatabaseViewTransaction).
///

@end
