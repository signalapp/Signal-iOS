#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseFullTextSearchPrivate.h"

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

@implementation YapDatabaseFullTextSearch

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent
{
	sqlite3 *db = transaction->connection->db;
	
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

+ (NSArray *)previousClassNames
{
	return @[ @"YapCollectionsDatabaseFullTextSearch" ];
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
@synthesize versionTag = versionTag;

- (id)initWithColumnNames:(NSArray *)inColumnNames
                  handler:(YapDatabaseFullTextSearchHandler *)inHandler
{
	return [self initWithColumnNames:inColumnNames options:nil handler:inHandler versionTag:nil];
}

- (id)initWithColumnNames:(NSArray *)inColumnNames
                    handler:(YapDatabaseFullTextSearchHandler *)inHandler
               versionTag:(NSString *)inVersionTag
{
	return [self initWithColumnNames:inColumnNames
	                         options:nil
	                         handler:inHandler
	                      versionTag:inVersionTag];
}

- (id)initWithColumnNames:(NSArray *)inColumnNames
                  options:(NSDictionary *)inOptions
                  handler:(YapDatabaseFullTextSearchHandler *)inHandler
               versionTag:(NSString *)inVersionTag
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
	
	NSAssert(inHandler != NULL, @"Null handler");
	
	if ((self = [super init]))
	{
		columnNames = [NSOrderedSet orderedSetWithArray:inColumnNames];
		columnNamesSharedKeySet = [NSDictionary sharedKeySetForKeys:[columnNames array]];
		
		options = [inOptions copy];
		
		block = inHandler.block;
		blockType = inHandler.blockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
	}
	return self;
}

/**
 * DEPRECATED
 * Use method initWithColumnNames:handler: instead.
**/
- (id)initWithColumnNames:(NSArray *)inColumnNames
                    block:(YapDatabaseFullTextSearchBlock)inBlock
                blockType:(YapDatabaseFullTextSearchBlockType)inBlockType
{
	YapDatabaseFullTextSearchHandler *handler =
	  [YapDatabaseFullTextSearchHandler withBlock:inBlock blockType:inBlockType];
	
	return [self initWithColumnNames:inColumnNames handler:handler];
}

/**
 * DEPRECATED
 * Use method initWithColumnNames:handler:versionTag: instead.
**/
- (id)initWithColumnNames:(NSArray *)inColumnNames
                    block:(YapDatabaseFullTextSearchBlock)inBlock
                blockType:(YapDatabaseFullTextSearchBlockType)inBlockType
                versionTag:(NSString *)inVersionTag
{
	YapDatabaseFullTextSearchHandler *handler =
	  [YapDatabaseFullTextSearchHandler withBlock:inBlock blockType:inBlockType];
	
	return [self initWithColumnNames:inColumnNames handler:handler versionTag:inVersionTag];
}

/**
 * DEPRECATED
 * Use method initWithColumnNames:options:handler:versionTag: instead.
**/
- (id)initWithColumnNames:(NSArray *)inColumnNames
                  options:(NSDictionary *)inOptions
                    block:(YapDatabaseFullTextSearchBlock)inBlock
                blockType:(YapDatabaseFullTextSearchBlockType)inBlockType
                versionTag:(NSString *)inVersionTag
{
	YapDatabaseFullTextSearchHandler *handler =
	  [YapDatabaseFullTextSearchHandler withBlock:inBlock blockType:inBlockType];
	
	return [self initWithColumnNames:inColumnNames options:inOptions handler:handler versionTag:inVersionTag];
}


- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseFullTextSearchConnection alloc] initWithFTS:self databaseConnection:databaseConnection];
}

- (NSString *)tableName
{
	return [[self class] tableNameForRegisteredName:self.registeredName];
}

@end
