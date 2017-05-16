#import "YapDatabaseAutoViewTransaction.h"
#import "YapDatabaseAutoViewPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapCache.h"
#import "YapCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

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


@implementation YapDatabaseAutoViewTransaction

#pragma mark Extension Lifecycle

- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Enumerate the existing rows in the database and populate the view
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[viewConnection getGrouping:&grouping
	                    sorting:&sorting];
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	BOOL needsObject = groupingNeedsObject || sortingNeedsObject;
	BOOL needsMetadata = groupingNeedsMetadata || sortingNeedsMetadata;
	
	NSString *(^getGroup)(NSString *collection, NSString *key, id object, id metadata);
	
	if (grouping->blockType == YapDatabaseBlockTypeWithKey)
	{
		getGroup = ^(NSString *collection, NSString *key, id __unused object, id __unused metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
		        (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key);
			return [group copy]; // mutable string protection
		};
	}
	else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
	{
		getGroup = ^(NSString *collection, NSString *key, id object, id __unused metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
		        (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, object);
			return [group copy]; // mutable string protection
		};
	}
	else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		getGroup = ^(NSString *collection, NSString *key, id __unused object, id metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
		        (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, metadata);
			return [group copy]; // mutable string protection
		};
	}
	else
	{
		getGroup = ^(NSString *collection, NSString *key, id object, id metadata){
			
			__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
		        (YapDatabaseViewGroupingWithRowBlock)grouping->block;
			
			NSString *group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			return [group copy]; // mutable string protection
		};
	}
	
	YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
	
	if (needsObject && needsMetadata)
	{
		if (groupingNeedsObject || groupingNeedsMetadata)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, object, metadata);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:object
					         metadata:metadata
					          inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *__unused outerStop) {
					
					if ([allowedCollections isAllowed:collection]) {
						[databaseTransaction _enumerateRowsInCollections:@[ collection ] usingBlock:block];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the object or metadata.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateRowsInCollections:@[ collection ]
						                                      usingBlock:block
						                                      withFilter:filter];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else if (needsObject && !needsMetadata)
	{
		if (groupingNeedsObject)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, object, nil);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:object
					          metadata:nil
					           inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ]
						                                                usingBlock:block];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the object.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key) {
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				          metadata:nil
				        inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ]
						                                                usingBlock:block
						                                                withFilter:filter];
					}
				}];
			}
			else // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else if (!needsObject && needsMetadata)
	{
		if (groupingNeedsMetadata)
		{
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop){
				
				NSString *group = getGroup(collection, key, nil, metadata);
				if (group)
				{
					YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[self insertRowid:rowid
					    collectionKey:collectionKey
					           object:nil
					         metadata:metadata
					          inGroup:group withChanges:flags isNew:YES];
				}
			};
			
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ]
						                                                 usingBlock:block];
					}
				}];
			}
			else  // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block];
			}
		}
		else
		{
			// Optimization: Grouping doesn't require the metadata.
			// So we can skip the deserialization step for any rows not in the view.
			
			__block NSString *group = nil;
			
			BOOL (^filter)(int64_t rowid, NSString *collection, NSString *key);
			filter = ^BOOL(int64_t __unused rowid, NSString *collection, NSString *key){
				
				group = getGroup(collection, key, nil, nil);
				return (group != nil);
			};
			
			void (^block)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
			block = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL __unused *stop){
				
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:nil
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:YES];
			};
			
			YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
			if (allowedCollections)
			{
				[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
					
					if ([allowedCollections isAllowed:collection])
					{
						[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ]
						                                                 usingBlock:block
						                                                 withFilter:filter];
					}
				}];
			}
			else  // if (!allowedCollections)
			{
				[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:filter];
			}
		}
	}
	else // if (!needsObject && !needsMetadata)
	{
		void (^block)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop);
		block = ^(int64_t rowid, NSString *collection, NSString *key, BOOL __unused *stop){
			
			NSString *group = getGroup(collection, key, nil, nil);
			if (group)
			{
				YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:nil
				         metadata:nil
				          inGroup:group withChanges:flags isNew:YES];
			}
		};
		
		YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL __unused *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysInCollections:@[ collection ] usingBlock:block];
				}
			}];
		}
		else  // if (!allowedCollections)
		{
			[databaseTransaction _enumerateKeysInAllCollectionsUsingBlock:block];
		}
	}
	
	return YES;
}

- (void)repopulateView
{
	YDBLogAutoTrace();
	
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * The object and metadata parameters must be properly set (if needed by the sorting block).
 * 
 * This method will use the configured sorting block to find the proper index for the key.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
             object:(id)object
           metadata:(id)metadata
            inGroup:(NSString *)group
        withChanges:(YapDatabaseViewChangesBitMask)flags
              isNew:(BOOL)isGuaranteedNew
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseViewSorting *sorting = nil;
	[viewConnection getGrouping:NULL sorting:&sorting];
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization during sorting.
	
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
	
	// Create a block to do a single sorting comparison between the object to be inserted,
	// and some other object within the group at a given index.
	//
	// This block will be invoked repeatedly as we calculate the insertion index.
	
	NSComparisonResult (^compare)(NSUInteger) = ^NSComparisonResult (NSUInteger index){
		
		int64_t anotherRowid = 0;
		[self getRowid:&anotherRowid atIndex:index inGroup:group];
		
		if (sorting->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseViewSortingWithKeyBlock sortingBlock =
			    (YapDatabaseViewSortingWithKeyBlock)sorting->block;
			
			YapCollectionKey *another = [databaseTransaction collectionKeyForRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,
			                            another.collection,       another.key);
		}
		else if (sorting->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseViewSortingWithObjectBlock sortingBlock =
			    (YapDatabaseViewSortingWithObjectBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherObject = nil;
			[databaseTransaction getCollectionKey:&another
			                               object:&anotherObject
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        object,
			                            another.collection,       another.key, anotherObject);
		}
		else if (sorting->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewSortingWithMetadataBlock sortingBlock =
			    (YapDatabaseViewSortingWithMetadataBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherMetadata = nil;
			[databaseTransaction getCollectionKey:&another
			                             metadata:&anotherMetadata
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        metadata,
			                            another.collection,       another.key, anotherMetadata);
		}
		else
		{
			__unsafe_unretained YapDatabaseViewSortingWithRowBlock sortingBlock =
			    (YapDatabaseViewSortingWithRowBlock)sorting->block;
			
			YapCollectionKey *another = nil;
			id anotherObject = nil;
			id anotherMetadata = nil;
			[databaseTransaction getCollectionKey:&another
			                               object:&anotherObject
			                             metadata:&anotherMetadata
			                             forRowid:anotherRowid];
			
			return sortingBlock(databaseTransaction, group,
			                      collectionKey.collection, collectionKey.key,        object,        metadata,
			                            another.collection,       another.key, anotherObject, anotherMetadata);
		}
	};
	
	NSComparisonResult cmp;
	
	// Optimization 1:
	//
	// If the key is already in the group, check to see if its index is the same as before.
	// This handles the common case where an object is updated without changing its position within the view.
	
	if (tryExistingIndexInGroup)
	{
		// Edge case: existing key is the only key in the group
		//
		// (existingIndex == 0) && (count == 1)
		
		NSUInteger existingIndexInGroup = existingLocator.index;
		BOOL useExistingIndexInGroup = YES;
		
		if (existingIndexInGroup > 0)
		{
			cmp = compare(existingIndexInGroup - 1); // compare vs prev
			
			useExistingIndexInGroup = (cmp != NSOrderedAscending); // object >= prev
		}
		
		if ((existingIndexInGroup + 1) < count && useExistingIndexInGroup)
		{
			cmp = compare(existingIndexInGroup + 1); // compare vs next
			
			useExistingIndexInGroup = (cmp != NSOrderedDescending); // object <= next
		}
		
		if (useExistingIndexInGroup)
		{
			// The key doesn't change position.
			
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
		
	// Optimization 2:
	//
	// A very common operation is to insert objects at the beginning or end of the array.
	// We attempt to notice this trend and optimize around it.
	
	if (viewConnection->lastInsertWasAtFirstIndex && (count > 1))
	{
		cmp = compare(0);
		
		if (cmp == NSOrderedAscending) // object < first
		{
			YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) at beginning (optimization)",
			              collectionKey.key, collectionKey.collection, group);
			
			[self insertRowid:rowid collectionKey:collectionKey
			                              inGroup:group
			                              atIndex:0];
			return;
		}
	}
	
	if (viewConnection->lastInsertWasAtLastIndex && (count > 1))
	{
		cmp = compare(count - 1);
		
		if (cmp != NSOrderedAscending) // object >= last
		{
			YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) at end (optimization)",
			              collectionKey.key, collectionKey.collection, group);
			
			[self insertRowid:rowid collectionKey:collectionKey
			                              inGroup:group
			                              atIndex:count];
			return;
		}
	}
	
	// Otherwise:
	//
	// Binary search operation.
	//
	// This particular algorithm accounts for cases where the objects are not unique.
	// That is, if some objects are NSOrderedSame, then the algorithm returns the largest index possible
	// (within the region where elements are "equal").
	
	NSUInteger loopCount = 0;
	
	NSUInteger min = 0;
	NSUInteger max = count;
	
	while (min < max)
	{
		NSUInteger mid = (min + max) / 2;
		
		cmp = compare(mid);
		
		if (cmp == NSOrderedAscending)
			max = mid;
		else
			min = mid + 1;
		
		loopCount++;
	}
	
	YDBLogVerbose(@"Insert key(%@) collection(%@) in group(%@) took %lu comparisons",
	              collectionKey.key, collectionKey.collection, group, (unsigned long)loopCount);
	
	[self insertRowid:rowid collectionKey:collectionKey
	                              inGroup:group
	                              atIndex:min];
	
	viewConnection->lastInsertWasAtFirstIndex = (min == 0);
	viewConnection->lastInsertWasAtLastIndex  = (min == count);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
                        object:(id)object
                      metadata:(id)metadata
                      grouping:(YapDatabaseViewGrouping *)grouping
                       sorting:(YapDatabaseViewSorting *)sorting
            blockInvokeBitMask:(YapDatabaseBlockInvoke)blockInvokeBitMask
                changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseView *view = (YapDatabaseView *)parentConnection->parent;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = view->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Determine if the grouping or sorting may have changed
	
	BOOL groupingMayHaveChanged;
	BOOL sortingMayHaveChanged;
	
	if (isInsert)
	{
		groupingMayHaveChanged = YES;
		sortingMayHaveChanged  = YES;
	}
	else
	{
		groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
		sortingMayHaveChanged  = (sorting->blockInvokeOptions & blockInvokeBitMask);
	}
	
	if (!groupingMayHaveChanged && !sortingMayHaveChanged)
	{
		// Nothing left to do.
		// Neither the groupingBlock or sortingBlock need to be run.
		
		YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
		
		if (locator.group)
		{
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:locator.group
			                                        atIndex:locator.index
			                                    withChanges:changesBitMask]];
		}
		
		return;
	}
	
	// Invoke the grouping block to find out if the row should be included in the view.
	
	NSString *group = nil;
	
	if (groupingMayHaveChanged)
	{
		if (grouping->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			    (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			    (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			    (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, metadata);
			group = [group copy]; // mutable string protection
		}
		else
		{
			__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			    (YapDatabaseViewGroupingWithRowBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			group = [group copy]; // mutable string protection
		}
		
		if (group == nil)
		{
			// Remove row from view (if needed).
			
			if (!isInsert)
			{
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			
			return;
		}
		
		if (!sortingMayHaveChanged)
		{
			YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
			
			if ([group isEqualToString:locator.group])
			{
				[parentConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:locator.group
				                                        atIndex:locator.index
				                                    withChanges:changesBitMask]];
				
				return;
			}
		}
	}
	else
	{
		// Grouping hasn't changed.
		// Fetch the current group.
		
		YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
		group = locator.group;
		
		if (group == nil)
		{
			// Nothing to do.
			// The row wasn't previously in the view, and still isn't in the view.
			
			return;
		}
	}
	
	// Add row to the view or update its position.
	
	[self insertRowid:rowid
	    collectionKey:collectionKey
	           object:object
	         metadata:metadata
	          inGroup:group
	      withChanges:changesBitMask
	            isNew:isInsert];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeOnInsertOnly;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:YES];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
	          blockInvokeBitMask:blockInvokeBitMask
	              changesBitMask:changesBitMask
	                    isInsert:NO];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
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
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
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
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
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
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	YapDatabaseBlockInvoke blockInvokeBitMask =
	  YapDatabaseBlockInvokeIfObjectTouched | YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting *sorting = nil;
	
	[viewConnection getGrouping:&grouping sorting:&sorting];
	
	BOOL groupingMayHaveChanged = (grouping->blockInvokeOptions & blockInvokeBitMask);
	BOOL sortingMayHaveChanged  = (sorting->blockInvokeOptions  & blockInvokeBitMask);
	
	BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
	BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
	
	BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
	BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
	
	id object = nil;
	if ((groupingMayHaveChanged && groupingNeedsObject) || (sortingMayHaveChanged && sortingNeedsObject))
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if ((groupingMayHaveChanged && groupingNeedsMetadata) || (sortingMayHaveChanged && sortingNeedsMetadata))
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata
	                    grouping:grouping
	                     sorting:sorting
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
#pragma mark Public API - Finding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for extensive documentation for this method.
**/
- (NSRange)findRangeInGroup:(NSString *)group using:(YapDatabaseViewFind *)find
{
	return [self findRangeInGroup:group using:find quitAfterOne:NO];
}

/**
 * This method uses a binary search algorithm to find an item within the view that matches the given criteria.
 * 
 * It works similarly to findRangeInGroup:using:, but immediately returns once a single match has been found.
 * This makes it more efficient when you only care about the existence of a match,
 * or you know there will never be more than a single match.
 *
 * See the documentation for findRangeInGroup:using: for more information.
 * @see findRangeInGroup:using:
 *
 * @return
 *   If found, the index of the first match discovered.
 *   That is, an item where the find block returned NSOrderedSame.
 *   If not found, returns NSNotFound.
**/
- (NSUInteger)findFirstMatchInGroup:(NSString *)group using:(YapDatabaseViewFind *)find
{
	NSRange range = [self findRangeInGroup:group using:find quitAfterOne:YES];
	
	return range.location;
}

/**
 * See header file for extensive documentation for this method.
**/
- (NSRange)findRangeInGroup:(NSString *)group using:(YapDatabaseViewFind *)find quitAfterOne:(BOOL)quitAfterOne
{
	if (group == nil || find == NULL)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	NSUInteger count = [self numberOfItemsInGroup:group];
	if (count == 0)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	// Helper block:
	//
	// Executes the findBlock against the row represented by the given index (within the view.group).
	
	NSComparisonResult (^compare)(NSUInteger);
		
	switch (find.findBlockType)
	{
		case YapDatabaseBlockTypeWithKey :
		{
			__unsafe_unretained YapDatabaseViewFindWithKeyBlock findBlock =
			  (YapDatabaseViewFindWithKeyBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = 0;
				[self getRowid:&rowid atIndex:index inGroup:group];
				
				YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
				
				return findBlock(ck.collection, ck.key);
			};
			
			break;
		}
		case YapDatabaseBlockTypeWithObject :
		{
			__unsafe_unretained YapDatabaseViewFindWithObjectBlock findBlock =
			    (YapDatabaseViewFindWithObjectBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = 0;
				[self getRowid:&rowid atIndex:index inGroup:group];
				
				YapCollectionKey *ck = nil;
				id object = nil;
				[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, object);
			};
			
			break;
		}
		case YapDatabaseBlockTypeWithMetadata :
		{
			__unsafe_unretained YapDatabaseViewFindWithMetadataBlock findBlock =
			    (YapDatabaseViewFindWithMetadataBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = 0;
				[self getRowid:&rowid atIndex:index inGroup:group];
				
				YapCollectionKey *ck = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, metadata);
			};
			
			break;
		}
		default :
		{
			__unsafe_unretained YapDatabaseViewFindWithRowBlock findBlock =
			    (YapDatabaseViewFindWithRowBlock)find.findBlock;
			
			compare = ^NSComparisonResult (NSUInteger index){
				
				int64_t rowid = 0;
				[self getRowid:&rowid atIndex:index inGroup:group];
				
				YapCollectionKey *ck = nil;
				id object = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid];
				
				return findBlock(ck.collection, ck.key, object, metadata);
			};
		}
		
	} // end switch (blockType)
		
	
	NSUInteger loopCount = 0;
	
	// Find first match (first to return NSOrderedSame)
	
	NSUInteger mMin = 0;
	NSUInteger mMax = count;
	NSUInteger mMid = 0;
	
	BOOL found = NO;
	
	while (mMin < mMax && !found)
	{
		mMid = (mMin + mMax) / 2;
		
		NSComparisonResult cmp = compare(mMid);
		
		if (cmp == NSOrderedDescending)      // Descending => value is greater than desired range
			mMax = mMid;
		else if (cmp == NSOrderedAscending)  // Ascending => value is less than desired range
			mMin = mMid + 1;
		else
			found = YES;
		
		loopCount++;
	}
	
	if (!found)
	{
		return NSMakeRange(NSNotFound, 0);
	}
	
	if (quitAfterOne)
	{
		return NSMakeRange(mMid, 1);
	}
	
	// Find start of range
	
	NSUInteger sMin = mMin;
	NSUInteger sMax = mMid;
	NSUInteger sMid;
	
	while (sMin < sMax)
	{
		sMid = (sMin + sMax) / 2;
		
		NSComparisonResult cmp = compare(sMid);
		
		if (cmp == NSOrderedAscending) // Ascending => value is less than desired range
			sMin = sMid + 1;
		else
			sMax = sMid;
		
		loopCount++;
	}
	
	// Find end of range
	
	NSUInteger eMin = mMid;
	NSUInteger eMax = mMax;
	NSUInteger eMid;
	
	while (eMin < eMax)
	{
		eMid = (eMin + eMax) / 2;
		
		NSComparisonResult cmp = compare(eMid);
		
		if (cmp == NSOrderedDescending) // Descending => value is greater than desired range
			eMax = eMid;
		else
			eMin = eMid + 1;
		
		loopCount++;
	}
	
	YDBLogVerbose(@"Find range in group(%@) took %lu comparisons", group, (unsigned long)loopCount);
	
	return NSMakeRange(sMin, (eMax - sMin));
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseAutoViewTransaction (ReadWrite)

/**
 * This method allows you to change the grouping and/or sorting on-the-fly.
 * 
 * Note: You must pass a different versionTag, or this method does nothing.
**/
- (void)setGrouping:(YapDatabaseViewGrouping *)grouping
            sorting:(YapDatabaseViewSorting *)sorting
         versionTag:(NSString *)inVersionTag
{
	YDBLogAutoTrace();
	
	NSAssert(grouping != nil, @"Invalid parameter: grouping == nil");
	NSAssert(sorting != nil, @"Invalid parameter: sorting == nil");
	
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
	
	__unsafe_unretained YapDatabaseAutoViewConnection *viewConnection =
	  (YapDatabaseAutoViewConnection *)parentConnection;
	
	[viewConnection setGrouping:grouping
	                    sorting:sorting
	                 versionTag:newVersionTag];
	
	[self repopulateView];
	
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
				int flags = YDB_GroupingMayHaveChanged | YDB_SortingMayHaveChanged;
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
}

@end
