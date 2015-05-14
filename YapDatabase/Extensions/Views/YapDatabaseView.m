#import "YapDatabaseView.h"
#import "YapDatabaseViewPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

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

@implementation YapDatabaseView

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent
{
	NSString *mapTableName = [self mapTableNameForRegisteredName:registeredName];
	NSString *pageTableName = [self pageTableNameForRegisteredName:registeredName];
	NSString *pageMetadataTableName = [self pageMetadataTableNameForRegisteredName:registeredName];
	
	if (wasPersistent)
	{
		// Handle persistent view
		
		sqlite3 *db = transaction->connection->db;
		
		NSString *dropKeyTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", mapTableName];
		NSString *dropPageTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", pageTableName];
		
		int status;
		
		status = sqlite3_exec(db, [dropKeyTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping map table (%@): %d %s",
			            THIS_METHOD, mapTableName, status, sqlite3_errmsg(db));
		}
		
		status = sqlite3_exec(db, [dropPageTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping page table (%@): %d %s",
			            THIS_METHOD, pageTableName, status, sqlite3_errmsg(db));
		}
	}
	else
	{
		// Handle memory view
		
		[transaction->connection unregisterMemoryTableWithName:mapTableName];
		[transaction->connection unregisterMemoryTableWithName:pageTableName];
		[transaction->connection unregisterMemoryTableWithName:pageMetadataTableName];
	}
}

+ (NSArray *)previousClassNames
{
	return @[ @"YapCollectionsDatabaseView" ];
}

+ (NSString *)mapTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_map", registeredName];
}

+ (NSString *)pageTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_page", registeredName];
}

+ (NSString *)pageMetadataTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_pageMetadata", registeredName];
}

/**
 * Allows you to fetch the versionTag from a view that was registered during the last app launch.
 * 
 * For example, let's say you have a view that sorts contacts.
 * And you support 2 different sort options:
 * - First, Last
 * - Last, First
 * 
 * To support this, you use 2 different versionTags:
 * - "First,Last"
 * - "Last,First"
 * 
 * And you want to ensure that when you first register the view (during app launch),
 * you choose the same block & versionTag from a previous app launch (if possible).
 * This prevents the view from enumerating the database & re-populating itself
 * during registration if the versionTag is different from last time.
 * 
 * So you can use this method to fetch the previous versionTag.
**/
+ (NSString *)previousVersionTagForRegisteredViewName:(NSString *)registeredName
                                      withTransaction:(YapDatabaseReadTransaction *)transaction
{
	NSString *prevVersionTag = [transaction stringValueForKey:ext_key_versionTag extension:registeredName];
	
	if (prevVersionTag == nil)
	{
		NSString *prevClassName = [transaction stringValueForKey:ext_key_class extension:registeredName];
		
		if ([prevClassName isEqualToString:@"YapDatabaseFilteredView"])
		{
			NSString *prevTag_deprecated =
			  [transaction stringValueForKey:ext_key_tag_deprecated extension:registeredName];
			
			if (prevTag_deprecated)
			{
				prevVersionTag = prevTag_deprecated;
			}
		}
		else
		{
			int prevVersion_deprecated = 0;
			BOOL hasPrevVersion_deprecated = [transaction getIntValue:&prevVersion_deprecated
			                                                   forKey:ext_key_version_deprecated
			                                                extension:registeredName];
			
			if (hasPrevVersion_deprecated)
			{
				prevVersionTag = [NSString stringWithFormat:@"%d", prevVersion_deprecated];
			}
		}
		
	}
	
	return prevVersionTag;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize groupingBlock = groupingBlock;
@synthesize sortingBlock = sortingBlock;

@synthesize groupingBlockType = groupingBlockType;
@synthesize sortingBlockType = sortingBlockType;

@synthesize versionTag = versionTag; // Getter is overriden
@dynamic options;

#pragma mark Init

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
{
	return [self initWithGrouping:grouping
	                      sorting:sorting
	                   versionTag:nil
	                      options:nil];
}

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(NSString *)inVersionTag
{
	return [self initWithGrouping:grouping
	                      sorting:sorting
	                   versionTag:inVersionTag
	                      options:nil];
}

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(NSString *)inVersionTag
                         options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert(grouping != NULL, @"Invalid parameter: grouping == nil");
	NSAssert(sorting != NULL, @"Invalid parameter: sorting == nil");
	
	if ((self = [super init]))
	{
		groupingBlock = grouping.groupingBlock;
		groupingBlockType = grouping.groupingBlockType;
		
		sortingBlock = sorting.sortingBlock;
		sortingBlockType = sorting.sortingBlockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseViewGroupingBlock)groupingBlock
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewGroupingBlock mostRecentGroupingBlock = NULL;
	dispatch_block_t block = ^{
		
		mostRecentGroupingBlock = groupingBlock;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentGroupingBlock;
}

- (YapDatabaseViewSortingBlock)sortingBlock
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewSortingBlock mostRecentSortingBlock = NULL;
	dispatch_block_t block = ^{
		
		mostRecentSortingBlock = sortingBlock;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentSortingBlock;
}

- (YapDatabaseViewBlockType)groupingBlockType
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewBlockType mostRecentGroupingBlockType = 0;
	dispatch_block_t block = ^{
		
		mostRecentGroupingBlockType = groupingBlockType;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentGroupingBlockType;
}

- (YapDatabaseViewBlockType)sortingBlockType
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewBlockType mostRecentSortingBlockType = 0;
	dispatch_block_t block = ^{
		
		mostRecentSortingBlockType = sortingBlockType;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentSortingBlockType;
}

- (NSString *)versionTag
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block NSString *mostRecentVersionTag = nil;
	
	dispatch_block_t block = ^{
		
		mostRecentVersionTag = versionTag;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentVersionTag;
}

- (YapDatabaseViewOptions *)options
{
	return [options copy]; // Our copy must remain immutable
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtension Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement this method IF they are non-persistent (in-memory only).
 * By doing so, they allow various optimizations, such as not persisting extension info in the yap2 table.
**/
- (BOOL)isPersistent
{
	return options.isPersistent;
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseViewConnection alloc] initWithView:self databaseConnection:databaseConnection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Table Names
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)mapTableName
{
	return [[self class] mapTableNameForRegisteredName:self.registeredName];
}

- (NSString *)pageTableName
{
	return [[self class] pageTableNameForRegisteredName:self.registeredName];
}

- (NSString *)pageMetadataTableName
{
	return [[self class] pageMetadataTableNameForRegisteredName:self.registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * This method is invoked on the snapshot queue.
 * The given changeset is the most recent commit.
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	YapDatabaseViewGroupingBlock newGroupingBlock = changeset[changeset_key_groupingBlock];
	if (newGroupingBlock)
	{
		groupingBlock = newGroupingBlock;
		groupingBlockType = [changeset[changeset_key_groupingBlockType] integerValue];
	}
	
	YapDatabaseViewSortingBlock newSortingBlock = changeset[changeset_key_sortingBlock];
	if (newSortingBlock)
	{
		sortingBlock = newSortingBlock;
		sortingBlockType = [changeset[changeset_key_sortingBlockType] integerValue];
	}
	
	NSString *newVersionTag = changeset[changeset_key_versionTag];
	if (newVersionTag)
	{
		versionTag = newVersionTag;
	}
	
	latestState = [changeset objectForKey:changeset_key_state];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Optimization - Used by [YapDatabaseViewTransaction prepareIfNeeded]
**/
- (BOOL)getState:(YapDatabaseViewState **)statePtr
   forConnection:(YapDatabaseViewConnection *)viewConnection
{
	__block BOOL result = NO;
	__block YapDatabaseViewState *state = nil;
	
	int64_t extConnectionSnapshot = [viewConnection->databaseConnection snapshot];
	
	dispatch_sync(viewConnection->databaseConnection->database->snapshotQueue, ^{
		
		int64_t extSnapshot = [viewConnection->databaseConnection->database snapshot];
		
		if (extConnectionSnapshot == extSnapshot)
		{
			result = YES;
			state = latestState;
		}
	});
	
	*statePtr = state;
	return result;
}

/**
 * Used by YapDatabaseViewConnection to fetch & cache the values for a readWriteTransaction.
**/
- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
       groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
            sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
        sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
{
	__block YapDatabaseViewGroupingBlock mostRecentGroupingBlock = NULL;
	__block YapDatabaseViewSortingBlock  mostRecentSortingBlock  = NULL;
	__block YapDatabaseViewBlockType mostRecentGroupingBlockType = 0;
	__block YapDatabaseViewBlockType mostRecentSortingBlockType  = 0;
	
	dispatch_block_t block = ^{
	
		mostRecentGroupingBlock     = groupingBlock;
		mostRecentGroupingBlockType = groupingBlockType;
		mostRecentSortingBlock      = sortingBlock;
		mostRecentSortingBlockType  = sortingBlockType;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	
	if (groupingBlockPtr)     *groupingBlockPtr     = mostRecentGroupingBlock;
	if (groupingBlockTypePtr) *groupingBlockTypePtr = mostRecentGroupingBlockType;
	if (sortingBlockPtr)      *sortingBlockPtr      = mostRecentSortingBlock;
	if (sortingBlockTypePtr)  *sortingBlockTypePtr  = mostRecentSortingBlockType;
}

@end
