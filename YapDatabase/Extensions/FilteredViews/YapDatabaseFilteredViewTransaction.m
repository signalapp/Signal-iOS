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

#define ExtKey_classVersion    @"classVersion"
#define ExtKey_persistent      @"persistent"
#define ExtKey_parentViewName  @"parentViewName"
#define ExtKey_tag_deprecated  @"tag"
#define ExtKey_versionTag      @"versionTag"

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
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)(viewConnection->view);
	
	int classVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
	BOOL isPersistent = [self isPersistentView];
	
	NSString *parentViewName = filteredView->parentViewName;
	NSString *versionTag = filteredView->versionTag;
	
	// Figure out what steps we need to take in order to register the view
	
	BOOL needsCreateTables = NO;
	
	BOOL oldIsPersistent = NO;
	BOOL hasOldIsPersistent = NO;
	
	NSString *oldParentViewName = nil;
	NSString *oldVersionTag = nil;
	
	// Check classVersion (the internal version number of view implementation)
	
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ExtKey_classVersion];
	
	if (!hasOldClassVersion)
	{
		needsCreateTables = YES;
	}
	else if (oldClassVersion != classVersion)
	{
		[self dropTablesForOldClassVersion:oldClassVersion];
		needsCreateTables = YES;
	}
	
	// Check persistence.
	// Need to properly transition from persistent to non-persistent, and vice-versa.
	
	if (!needsCreateTables || hasOldClassVersion)
	{
		hasOldIsPersistent = [self getBoolValue:&oldIsPersistent forExtensionKey:ExtKey_persistent];
		
		if (hasOldIsPersistent && oldIsPersistent && !isPersistent)
		{
			[[viewConnection->view class]
			  dropTablesForRegisteredName:[self registeredName]
			              withTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction];
		}
		
		if (!hasOldIsPersistent || (oldIsPersistent != isPersistent))
		{
			needsCreateTables = YES;
		}
		else if (!isPersistent)
		{
			// We always have to create & populate the tables for non-persistent views.
			// Even when re-registering from previous app launch.
			needsCreateTables = YES;
			
			oldParentViewName = [self stringValueForExtensionKey:ExtKey_parentViewName];
			oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag];
		}
	}
	
	// Create or re-populate if needed
	
	if (needsCreateTables)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self populateView]) return NO;
		
		if (!hasOldClassVersion || (oldClassVersion != classVersion)) {
			[self setIntValue:classVersion forExtensionKey:ExtKey_classVersion];
		}
		
		if (!hasOldIsPersistent || (oldIsPersistent != isPersistent)) {
			[self setBoolValue:isPersistent forExtensionKey:ExtKey_persistent];
		}
		
		if (![oldParentViewName isEqualToString:parentViewName]) {
			[self setStringValue:parentViewName forExtensionKey:ExtKey_parentViewName];
		}
		
		if (![oldVersionTag isEqualToString:versionTag]) {
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag];
		}
	}
	else
	{
		BOOL needsRepopulateView = NO;
		
		// Check parentViewName.
		// Need to re-populate if the parent changed.
		
		oldParentViewName = [self stringValueForExtensionKey:ExtKey_parentViewName];
		
		if (![oldParentViewName isEqualToString:parentViewName])
		{
			needsRepopulateView = YES;
		}
		
		// Check user-supplied tag.
		// We may need to re-populate the database if the groupingBlock or sortingBlock changed.
		
		oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag];
		
		NSString *oldTag_deprecated = nil;
		if (oldVersionTag == nil)
		{
			oldTag_deprecated = [self stringValueForExtensionKey:ExtKey_tag_deprecated];
			if (oldTag_deprecated)
			{
				oldVersionTag = oldTag_deprecated;
			}
		}
		
		if (![oldVersionTag isEqualToString:versionTag])
		{
			needsRepopulateView = YES;
		}
		
		if (needsRepopulateView)
		{
			if (![self populateView]) return NO;
			
			if (![oldParentViewName isEqualToString:parentViewName]) {
				[self setStringValue:parentViewName forExtensionKey:ExtKey_parentViewName];
			}
			
			if (![oldVersionTag isEqualToString:versionTag]) {
				[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag];
			}
			
			if (oldTag_deprecated)
				[self removeValueForExtensionKey:ExtKey_tag_deprecated];
		}
		else if (oldTag_deprecated)
		{
			[self removeValueForExtensionKey:ExtKey_tag_deprecated];
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag];
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
				YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:ck inGroup:group atIndex:filteredIndex
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
				YapCollectionKey *ck = nil;
				id object = nil;
				[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, object))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:ck inGroup:group atIndex:filteredIndex
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
				YapCollectionKey *ck = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, metadata))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:ck inGroup:group atIndex:filteredIndex
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
				YapCollectionKey *ck = nil;
				id object = nil;
				id metadata = nil;
				
				[databaseTransaction getCollectionKey:&ck
				                               object:&object
				                             metadata:&metadata
				                             forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, object, metadata))
				{
					if (filteredIndex == 0)
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					else
						[self insertRowid:rowid collectionKey:ck inGroup:group atIndex:filteredIndex
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

- (void)repopulateView
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
				YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key))
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
				YapCollectionKey *ck = nil;
				id object = nil;
				[databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, object))
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
				YapCollectionKey *ck = nil;
				id metadata = nil;
				[databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, metadata))
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
				YapCollectionKey *ck = nil;
				id object = nil;
				id metadata = nil;
				
				[databaseTransaction getCollectionKey:&ck
				                              object:&object
				                            metadata:&metadata
				                            forRowid:rowid];
				
				if (filterBlock(group, ck.collection, ck.key, object, metadata))
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
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
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
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
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
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	BOOL groupMayHaveChanged = filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                           filteredView->groupingBlockType == YapDatabaseViewBlockTypeWithObject;
	
	BOOL sortMayHaveChanged = filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
	                          filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithObject;
	
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
	                            filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithObject;
	
	if (!groupMayHaveChanged && !sortMayHaveChanged && !filterMayHaveChanged)
	{
		// Nothing has changed that could possibly affect the view.
		// Just note the touch.
		
		int flags = YapDatabaseViewChangedObject;
		
		NSString *pageKey = [self pageKeyForRowid:rowid];
		NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
		
		[viewConnection->changes addObject:
		    [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
		
		lastHandledGroup = group;
		return;
	}
	
	// Ask filter block if we should add key to view.
	
	BOOL passesFilter;
	id metadata = nil;
	
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
		
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, metadata);
	}
	else // if (filteredView->filteringBlockType == YapDatabaseViewBlockTypeWithRow)
	{
		YapDatabaseViewFilteringWithRowBlock filterBlock =
		  (YapDatabaseViewFilteringWithRowBlock)filteredView->filteringBlock;
		
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		BOOL sortingBlockNeedsMetadata = filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                                 filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata;
		if (sortingBlockNeedsMetadata && metadata == nil)
		{
			metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
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

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
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
		
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
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
		
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
		passesFilter = filterBlock(group, collection, key, object, metadata);
	}
	
	if (passesFilter)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		BOOL sortingBlockNeedsObject = filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                               filteredView->sortingBlockType == YapDatabaseViewBlockTypeWithObject;
		if (sortingBlockNeedsObject && object == nil)
		{
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
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
- (void)viewDidRepopulate:(NSString *)parentViewName
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
	
	[self repopulateView];
	
	// Propogate the notification onward to any extensions dependent upon this one.
	
	__unsafe_unretained NSString *registeredName = [self registeredName];
	__unsafe_unretained NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(viewDidRepopulate:)])
			{
				[(id <YapDatabaseViewDependency>)extTransaction viewDidRepopulate:registeredName];
			}
		}
	}];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseFilteredViewTransaction (ReadWrite)

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
       filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
               versionTag:(NSString *)inVersionTag

{
	YDBLogAutoTrace();
	
	NSAssert(inFilteringBlock != NULL, @"Invalid filteringBlock");
	
	NSAssert(inFilteringBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid filteringBlockType");
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	__unsafe_unretained YapDatabaseFilteredView *filteredView =
	  (YapDatabaseFilteredView *)viewConnection->view;
	
	NSString *newVersionTag = inVersionTag ? [inVersionTag copy] : @"";
	
	if ([filteredView->versionTag isEqualToString:newVersionTag])
	{
		YDBLogWarn(@"%@ - versionTag didn't change, so not updating view", THIS_METHOD);
		return;
	}
	
	filteredView->filteringBlock = inFilteringBlock;
	filteredView->filteringBlockType = inFilteringBlockType;
	
	filteredView->versionTag = newVersionTag;
	
	[self repopulateView];
	[self setStringValue:newVersionTag forExtensionKey:ExtKey_versionTag];
	
	// Notify any extensions dependent upon this one that we repopulated.
	
	NSString *registeredName = [self registeredName];
	NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(viewDidRepopulate:)])
			{
				[(id <YapDatabaseViewDependency>)extTransaction viewDidRepopulate:registeredName];
			}
		}
	}];
}

@end
