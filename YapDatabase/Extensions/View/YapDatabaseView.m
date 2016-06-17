#import "YapDatabaseView.h"
#import "YapDatabaseViewPrivate.h"

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


@implementation YapDatabaseView

@synthesize versionTag = versionTag; // Getter is overriden
@dynamic options;

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
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)init
{
	NSString *reason = @"YapDatabaseView is an abstract class.";
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	  @"Use a concrete subclass of YapDatabaseView, such as YapDatabaseAutoView." };
	
	@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	
	return nil;
}

- (instancetype)initWithVersionTag:(NSString *)inVersionTag
                           options:(YapDatabaseViewOptions *)inOptions
{
	if ((self = [super init]))
	{
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	__unsafe_unretained YapDatabaseConnection *databaseConnection = viewConnection->databaseConnection;
	__unsafe_unretained YapDatabase *database = databaseConnection->database;
	
	__block BOOL result = NO;
	__block YapDatabaseViewState *state = nil;
	
	int64_t extConnectionSnapshot = [databaseConnection snapshot];
	dispatch_block_t block = ^{ @autoreleasepool {
		
		int64_t extSnapshot = [database snapshot];
		
		if (extConnectionSnapshot == extSnapshot)
		{
			result = YES;
			state = latestState;
		}
	}};
	
	if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
		block();
	else
		dispatch_sync(database->snapshotQueue, block);
	
	*statePtr = state;
	return result;
}

@end
