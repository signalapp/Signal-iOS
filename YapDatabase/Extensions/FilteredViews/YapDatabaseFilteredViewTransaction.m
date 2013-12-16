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
	BOOL needsCreateTables = NO;
	
	// Check classVersion (the internal version number of view implementation)
	
	int oldClassVersion = [self intValueForExtensionKey:@"classVersion"];
	int classVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
	
	if (oldClassVersion != classVersion)
		needsCreateTables = YES;
	
	// Check persistence.
	// Need to properly transition from persistent to non-persistent, and vice-versa.
	
	BOOL oldIsPersistent = NO;
	BOOL hasOldIsPersistent = [self getBoolValue:&oldIsPersistent forExtensionKey:@"persistent"];
	
	BOOL isPersistent = [self isPersistentView];
	
	if (hasOldIsPersistent && (oldIsPersistent != isPersistent))
	{
		[[viewConnection->view class]
		  dropTablesForRegisteredName:[self registeredName]
		              withTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction];
		
		needsCreateTables = YES;
	}
	
	// Create or re-populate if needed
	
	if (needsCreateTables)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self populateView]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:@"classVersion"];
		
		[self setBoolValue:isPersistent forExtensionKey:@"persistent"];
		
		int userSuppliedConfigVersion = viewConnection->view->version;
		[self setIntValue:userSuppliedConfigVersion forExtensionKey:@"version"];
	}
	else
	{
		// Check user-supplied tag.
		// We may need to re-populate the database if the groupingBlock or sortingBlock changed.
		
		__unsafe_unretained YapDatabaseFilteredView *filteredView =
		  (YapDatabaseFilteredView *)viewConnection->view;
		
		NSString *oldTag = [self stringValueForExtensionKey:@"tag"];
		NSString *newTag = filteredView->tag;
		
		if (![oldTag isEqualToString:newTag])
		{
			if (![self populateView]) return NO;
			
			[self setStringValue:newTag forExtensionKey:@"tag"];
		}
		
		if (!hasOldIsPersistent)
		{
			[self setBoolValue:isPersistent forExtensionKey:@"persistent"];
		}
	}
	
	return YES;
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
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
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
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
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
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
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
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
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
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)repopulate
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:filteredView->parentViewName];
	
	// Code overview:
	//
	// The objective is to enumerate the parentView, and invoke the new filter on each row.
	// However, we want our changeset to properly match what actually changes.
	// That is, we don't want to simply reset our view, and then repopulate from scratch.
	// We want our changeset to specify the exact diff,
	// highlighting just those items that were ultimately added or removed.
	// This will allow for smooth animations when changing the filter.
	//
	// For example, in Apple's phone app, in the Recents tab, one can switch between "all" and "missed" calls.
	// Tapping the "missed" button smoothly animates away all non-red rows. It looks great.
	// This is what we're going for.
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block BOOL existing = NO;
			__block int64_t existingRowid = 0;
			
			existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
			
			__block NSUInteger index = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				[databaseTransaction getKey:&key collection:&collection forRowid:rowid];
				
				if (filterBlock(group, collection, key))
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
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
						if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil))
							[self insertRowid:rowid collectionKey:ck inNewGroup:group];
						else
							[self insertRowid:rowid collectionKey:ck inGroup:group
							                                         atIndex:index withExistingPageKey:nil];
						index++;
					}
				}
				else
				{
					if (existing && (existingRowid == rowid))
					{
						// The row was previously in the view (allowed by previous filter),
						// but is no longer in the view (disallowed by new filter).
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
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
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block BOOL existing = NO;
			__block int64_t existingRowid = 0;
			
			existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
			
			__block NSUInteger index = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				id object = nil;
				[databaseTransaction getKey:&key collection:&collection object:&object forRowid:rowid];
				
				if (filterBlock(group, collection, key, object))
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
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
						if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil))
							[self insertRowid:rowid collectionKey:ck inNewGroup:group];
						else
							[self insertRowid:rowid collectionKey:ck inGroup:group
							                                         atIndex:index withExistingPageKey:nil];
						index++;
					}
				}
				else
				{
					if (existing && (existingRowid == rowid))
					{
						// The row was previously in the view (allowed by previous filter),
						// but is no longer in the view (disallowed by new filter).
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
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
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block BOOL existing = NO;
			__block int64_t existingRowid = 0;
			
			existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
			
			__block NSUInteger index = 0;
			
			[parentViewTransaction enumerateRowidsInGroup:group
			                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
			{
				NSString *key = nil;
				NSString *collection = nil;
				id metadata = nil;
				[databaseTransaction getKey:&key collection:&collection metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, collection, key, metadata))
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
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
						if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil))
							[self insertRowid:rowid collectionKey:ck inNewGroup:group];
						else
							[self insertRowid:rowid collectionKey:ck inGroup:group
							                                         atIndex:index withExistingPageKey:nil];
						index++;
					}
				}
				else
				{
					if (existing && (existingRowid == rowid))
					{
						// The row was previously in the view (allowed by previous filter),
						// but is no longer in the view (disallowed by new filter).
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
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
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		for (NSString *group in [parentViewTransaction allGroups])
		{
			__block BOOL existing = NO;
			__block int64_t existingRowid = 0;
			
			existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
			
			__block NSUInteger index = 0;
			
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
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
						if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil))
							[self insertRowid:rowid collectionKey:ck inNewGroup:group];
						else
							[self insertRowid:rowid collectionKey:ck inGroup:group
							                                         atIndex:index withExistingPageKey:nil];
						index++;
					}
				}
				else
				{
					if (existing && (existingRowid == rowid))
					{
						// The row was previously in the view (allowed by previous filter),
						// but is no longer in the view (disallowed by new filter).
						
						YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
						
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
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtensionTransaction_Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction =
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
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
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
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object
                    forKey:(NSString *)key
              inCollection:(NSString *)collection
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction =
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
	
	if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithKey)
	{
		YapDatabaseViewFilteringWithKeyBlock filterBlock =
		  (YapDatabaseViewFilteringWithKeyBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
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
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateMetadata:(id)metadata
                      forKey:(NSString *)key
                inCollection:(NSString *)collection
                   withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	BOOL groupMayHaveChanged = filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                           filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata;
	
	BOOL sortMayHaveChanged = filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                          filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata;
	
	// Instead of going to the groupingBlock,
	// just ask the parentViewTransaction what the last group was.
	
	YapDatabaseViewTransaction *parentViewTransaction =
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
		    [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
		
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
		
		passesFilter = filterBlock(group, collection, key);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject)
	{
		YapDatabaseViewFilteringWithObjectBlock filterBlock =
		  (YapDatabaseViewFilteringWithObjectBlock)filteredView->filteringBlock;
		
		object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, object);
	}
	else if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithMetadata)
	{
		YapDatabaseViewFilteringWithMetadataBlock filterBlock =
		  (YapDatabaseViewFilteringWithMetadataBlock)filteredView->filteringBlock;
		
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseFilteredViewTransaction (ReadWrite)

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
       filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                      tag:(NSString *)inTag

{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	NSString *newTag = inTag ? [inTag copy] : @"";
	
	if ([filteredView->tag isEqualToString:newTag])
	{
		YDBLogWarn(@"%@ - Tag didn't change, so not updating view", THIS_METHOD);
		return;
	}
	
	filteredView->filteringBlock = inFilteringBlock;
	filteredView->filteringBlockType = inFilteringBlockType;
	
	filteredView->tag = newTag;
	
	[self repopulate];
}

@end
