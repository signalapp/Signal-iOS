#import "YapCollectionsDatabaseView.h"
#import "YapCollectionsDatabaseViewPrivate.h"

#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"

#import "YapCollectionsDatabase.h"
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

@implementation YapCollectionsDatabaseView

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	sqlite3 *db = transaction->abstractConnection->db;
	
	NSString *keyTableName = [self keyTableNameForRegisteredName:registeredName];
	NSString *pageTableName = [self pageTableNameForRegisteredName:registeredName];
	
	NSString *dropKeyTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", keyTableName];
	NSString *dropPageTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", pageTableName];
	
	int status;
	
	status = sqlite3_exec(db, [dropKeyTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping key table (%@): %d %s",
		            THIS_METHOD, keyTableName, status, sqlite3_errmsg(db));
	}
	
	status = sqlite3_exec(db, [dropPageTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping page table (%@): %d %s",
		            THIS_METHOD, pageTableName, status, sqlite3_errmsg(db));
	}
}

+ (NSString *)keyTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"ckv_view_%@_key", registeredName];
}

+ (NSString *)pageTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"ckv_view_%@_page", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize groupingBlock = groupingBlock;
@synthesize sortingBlock = sortingBlock;

@synthesize groupingBlockType = groupingBlockType;
@synthesize sortingBlockType = sortingBlockType;

@synthesize version = version;

- (id)initWithGroupingBlock:(YapCollectionsDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapCollectionsDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapCollectionsDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapCollectionsDatabaseViewBlockType)inSortingBlockType
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:0];
}

- (id)initWithGroupingBlock:(YapCollectionsDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapCollectionsDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapCollectionsDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapCollectionsDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
{
	if ((self = [super init]))
	{
		NSAssert(inGroupingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
		         inGroupingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject ||
		         inGroupingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata ||
		         inGroupingBlockType == YapCollectionsDatabaseViewBlockTypeWithRow,
		         @"Invalid grouping block type");
		
		NSAssert(inSortingBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
		         inSortingBlockType == YapCollectionsDatabaseViewBlockTypeWithObject ||
		         inSortingBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata ||
		         inSortingBlockType == YapCollectionsDatabaseViewBlockTypeWithRow,
		         @"Invalid sorting block type");
		
		groupingBlock = inGroupingBlock;
		groupingBlockType = inGroupingBlockType;
		
		sortingBlock = inSortingBlock;
		sortingBlockType = inSortingBlockType;
		
		version = inVersion;
	}
	return self;
}

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 *
 * Return YES if the class/instance supports the particular type of database (YapDatabase vs YapCollectionsDatabase).
**/
- (BOOL)supportsDatabase:(YapAbstractDatabase *)database
{
	if ([database isKindOfClass:[YapCollectionsDatabase class]])
	{
		return YES;
	}
	else
	{
		YDBLogError(@"YapCollectionsDatabaseView only supports YapCollectionsDatabase, not YapDatabase");
		return NO;
	}
}

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	return [[YapCollectionsDatabaseViewConnection alloc] initWithView:self
	           databaseConnection:(YapCollectionsDatabaseConnection *)databaseConnection];
}

- (NSString *)keyTableName
{
	return [[self class] keyTableNameForRegisteredName:self.registeredName];
}

- (NSString *)pageTableName
{
	return [[self class] pageTableNameForRegisteredName:self.registeredName];
}

@end
