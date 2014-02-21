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
{
	NSString *mapTableName = [self mapTableNameForRegisteredName:registeredName];
	NSString *pageTableName = [self pageTableNameForRegisteredName:registeredName];
	NSString *pageMetadataTableName = [self pageMetadataTableNameForRegisteredName:registeredName];
	
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
	
	// Handle memory view
	
	[transaction->connection unregisterTableWithName:mapTableName];
	[transaction->connection unregisterTableWithName:pageTableName];
	[transaction->connection unregisterTableWithName:pageMetadataTableName];
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize groupingBlock = groupingBlock;
@synthesize sortingBlock = sortingBlock;

@synthesize groupingBlockType = groupingBlockType;
@synthesize sortingBlockType = sortingBlockType;

@synthesize versionTag = versionTag;
@dynamic options;

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                        versionTag:@""
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                 versionTag:(NSString *)inVersionTag
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                        versionTag:inVersionTag
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                 versionTag:(NSString *)inVersionTag
                    options:(YapDatabaseViewOptions *)inOptions
{
	if ((self = [super init]))
	{
		NSAssert(inGroupingBlock != NULL, @"Invalid grouping block");
		NSAssert(inSortingBlock != NULL, @"Invalid sorting block");
		
		NSAssert(inGroupingBlockType == YapDatabaseViewBlockTypeWithKey ||
		         inGroupingBlockType == YapDatabaseViewBlockTypeWithObject ||
		         inGroupingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
		         inGroupingBlockType == YapDatabaseViewBlockTypeWithRow,
		         @"Invalid grouping block type");
		
		NSAssert(inSortingBlockType == YapDatabaseViewBlockTypeWithKey ||
		         inSortingBlockType == YapDatabaseViewBlockTypeWithObject ||
		         inSortingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
		         inSortingBlockType == YapDatabaseViewBlockTypeWithRow,
		         @"Invalid sorting block type");
		
		groupingBlock = inGroupingBlock;
		groupingBlockType = inGroupingBlockType;
		
		sortingBlock = inSortingBlock;
		sortingBlockType = inSortingBlockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

- (YapDatabaseViewOptions *)options
{
	return [options copy];
}

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports
 * the database configuration.
**/
- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	return YES;
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseViewConnection alloc] initWithView:self databaseConnection:databaseConnection];
}

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

@end
