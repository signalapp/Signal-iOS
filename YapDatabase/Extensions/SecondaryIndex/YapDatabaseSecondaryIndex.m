#import "YapDatabaseSecondaryIndex.h"
#import "YapDatabaseSecondaryIndexPrivate.h"

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


@implementation YapDatabaseSecondaryIndex

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
	sqlite3 *db = transaction->connection->db;
	NSString *tableName = [self tableNameForRegisteredName:registeredName];
	
	NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", tableName];
	
	int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping table (%@): %d %s",
		            THIS_METHOD, tableName, status, sqlite3_errmsg(db));
	}
}

+ (NSArray *)previousClassNames
{
	return @[ @"YapCollectionsDatabaseSecondaryIndex" ];
}

+ (NSString *)tableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"secondaryIndex_%@", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize version = version;

- (id)init
{
	NSAssert(NO, @"Must use designated initializer");
	return nil;
}

- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)inSetup
              block:(YapDatabaseSecondaryIndexBlock)inBlock
          blockType:(YapDatabaseSecondaryIndexBlockType)inBlockType
{
	return [self initWithSetup:inSetup block:inBlock blockType:inBlockType version:0];
}

- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)inSetup
              block:(YapDatabaseSecondaryIndexBlock)inBlock
          blockType:(YapDatabaseSecondaryIndexBlockType)inBlockType
            version:(int)inVersion
{
	// Sanity checks
	
	if (inSetup == nil)
	{
		NSAssert(NO, @"Invalid setup: nil");
		
		YDBLogError(@"%@: Invalid setup: nil", THIS_METHOD);
		return nil;
	}
	
	if ([inSetup count] == 0)
	{
		NSAssert(NO, @"Invalid setup: empty");
		
		YDBLogError(@"%@: Invalid setup: empty", THIS_METHOD);
		return nil;
	}
	
	if (inBlock == NULL)
	{
		NSAssert(NO, @"Invalid block: NULL");
		
		YDBLogError(@"%@: Invalid block: NULL", THIS_METHOD);
		return nil;
	}
	
	if (inBlockType != YapDatabaseSecondaryIndexBlockTypeWithKey      &&
	    inBlockType != YapDatabaseSecondaryIndexBlockTypeWithObject   &&
	    inBlockType != YapDatabaseSecondaryIndexBlockTypeWithMetadata &&
	    inBlockType != YapDatabaseSecondaryIndexBlockTypeWithRow       )
	{
		NSAssert(NO, @"Invalid blockType");
		
		YDBLogError(@"%@: Invalid blockType", THIS_METHOD);
		return nil;
	}
	
	// Looks sane, proceed with normal init
	
	if ((self = [super init]))
	{
		setup = [inSetup copy];
		
		block = inBlock;
		blockType = inBlockType;
		
		columnNamesSharedKeySet = [NSDictionary sharedKeySetForKeys:[setup columnNames]];
		
		version = inVersion;
	}
	return self;
}

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 *
 * Return YES if the class/instance supports the particular type of database (YapDatabase vs YapDatabase).
**/
- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions;
{
	if ([database isKindOfClass:[YapDatabase class]])
	{
		return YES;
	}
	else
	{
		YDBLogError(@"YapDatabaseSecondaryIndex only supports YapDatabase, not YapDatabase."
		            @"You want YapDatabaseSecondaryIndex.");
		return NO;
	}
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseSecondaryIndexConnection alloc]
	           initWithSecondaryIndex:self
	               databaseConnection:databaseConnection];
}

- (NSString *)tableName
{
	return [[self class] tableNameForRegisteredName:self.registeredName];
}

@end
