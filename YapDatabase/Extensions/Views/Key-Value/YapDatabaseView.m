#import "YapDatabaseView.h"
#import "YapDatabaseViewPrivate.h"

#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"

#import "YapDatabase.h"
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
                    withTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	NSString *mapTableName = [self mapTableNameForRegisteredName:registeredName];
	NSString *pageTableName = [self pageTableNameForRegisteredName:registeredName];
	NSString *pageMetadataTableName = [self pageMetadataTableNameForRegisteredName:registeredName];
	
	// Handle persistent view
	
	sqlite3 *db = transaction->abstractConnection->db;
	
	NSString *dropMapTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", mapTableName];
	NSString *dropPageTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", pageTableName];
	
	int status;
	
	status = sqlite3_exec(db, [dropMapTable UTF8String], NULL, NULL, NULL);
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
	
	[transaction->abstractConnection unregisterTableWithName:mapTableName];
	[transaction->abstractConnection unregisterTableWithName:pageTableName];
	[transaction->abstractConnection unregisterTableWithName:pageMetadataTableName];
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
	return [NSString stringWithFormat:@"view_%@_pageMetadata", registeredName]; // Only used for in-memory tables
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize groupingBlock = groupingBlock;
@synthesize sortingBlock = sortingBlock;

@synthesize groupingBlockType = groupingBlockType;
@synthesize sortingBlockType = sortingBlockType;

@synthesize version = version;
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
	                           version:0
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:inVersion
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
                    options:(YapDatabaseViewOptions *)inOptions;
{
	NSAssert(inGroupingBlock != NULL, @"Invalid groupingBlock");
	NSAssert(inSortingBlock != NULL, @"Invalid sortingBlock");
	
	NSAssert(inGroupingBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid groupingBlockType");
	
	NSAssert(inSortingBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid sortingBlockType");
	
	if ((self = [super init]))
	{
		groupingBlock = inGroupingBlock;
		groupingBlockType = inGroupingBlockType;
		
		sortingBlock = inSortingBlock;
		sortingBlockType = inSortingBlockType;
		
		version = inVersion;
		
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
 * This method is called during the view registration process to enusre the extension supports the database type.
 *
 * Return YES if the class/instance supports the particular type of database (YapDatabase vs YapCollectionsDatabase).
**/
- (BOOL)supportsDatabase:(YapAbstractDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	if ([database isKindOfClass:[YapDatabase class]])
	{
		return YES;
	}
	else
	{
		YDBLogError(@"YapDatabaseView only supports YapDatabase, not YapCollectionsDatabase");
		return NO;
	}
}

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseViewConnection alloc] initWithView:self
	                                    databaseConnection:(YapDatabaseConnection *)databaseConnection];
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
