#import "YapCollectionsDatabaseFullTextSearch.h"
#import "YapCollectionsDatabaseFullTextSearchPrivate.h"
#import "YapCollectionsDatabase.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
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

@implementation YapCollectionsDatabaseFullTextSearch

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	sqlite3 *db = transaction->abstractConnection->db;
	
	NSString *tableName = [self tableNameForRegisteredName:registeredName];
	NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", tableName];
	
	int status;
	
	status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping FTS table (%@): %d %s",
		            THIS_METHOD, dropTable, status, sqlite3_errmsg(db));
	}
}

+ (NSString *)tableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"fts_%@", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize version = version;

- (id)initWithColumnNames:(NSArray *)inColumnNames
                    block:(YapCollectionsDatabaseFullTextSearchBlock)inBlock
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)inBlockType
{
	return [self initWithColumnNames:inColumnNames options:nil block:inBlock blockType:inBlockType version:0];
}

- (id)initWithColumnNames:(NSArray *)inColumnNames
                    block:(YapCollectionsDatabaseFullTextSearchBlock)inBlock
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)inBlockType
                  version:(int)inVersion
{
	return [self initWithColumnNames:inColumnNames options:nil block:inBlock blockType:inBlockType version:inVersion];
}

- (id)initWithColumnNames:(NSArray *)inColumnNames
                  options:(NSDictionary *)inOptions
                    block:(YapCollectionsDatabaseFullTextSearchBlock)inBlock
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)inBlockType
                  version:(int)inVersion
{
	if ([inColumnNames count] == 0)
	{
		NSAssert(NO, @"Empty columnNames array");
		return nil;
	}
	
	for (id columnName in inColumnNames)
	{
		if (![columnName isKindOfClass:[NSString class]])
		{
			NSAssert(NO, @"Invalid column name. Not a string: %@", columnName);
			return nil;
		}
		
		NSRange range = [(NSString *)columnName rangeOfString:@"\""];
		if (range.location != NSNotFound)
		{
			NSAssert(NO, @"Invalid column name. Cannot contain quotes: %@", columnName);
			return nil;
		}
	}
	
	NSAssert(inBlock != NULL, @"Null block");
	
	NSAssert(inBlockType == YapCollectionsDatabaseFullTextSearchBlockTypeWithKey ||
	         inBlockType == YapCollectionsDatabaseFullTextSearchBlockTypeWithObject ||
	         inBlockType == YapCollectionsDatabaseFullTextSearchBlockTypeWithMetadata ||
	         inBlockType == YapCollectionsDatabaseFullTextSearchBlockTypeWithRow,
	         @"Invalid block type");
	
	if ((self = [super init]))
	{
		columnNames = [NSOrderedSet orderedSetWithArray:inColumnNames];
		columnNamesSharedKeySet = [NSDictionary sharedKeySetForKeys:[columnNames array]];
		
		options = [inOptions copy];
		
		block = inBlock;
		blockType = inBlockType;
		
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
		YDBLogError(@"YapCollectionsDatabaseFullTextSearch only supports YapCollectionsDatabase, not YapDatabase");
		return NO;
	}
}

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	return [[YapCollectionsDatabaseFullTextSearchConnection alloc] initWithFTS:self
	                    databaseConnection:(YapCollectionsDatabaseConnection *)databaseConnection];
}

- (NSString *)tableName
{
	return [[self class] tableNameForRegisteredName:self.registeredName];
}

@end
