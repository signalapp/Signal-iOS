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
#pragma unused(ydbLogLevel)


@implementation YapDatabaseSecondaryIndex

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL __unused)wasPersistent
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

@synthesize versionTag = versionTag;

- (id)init
{
	NSAssert(NO, @"Must use designated initializer");
	return nil;
}

- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)inSetup
            handler:(YapDatabaseSecondaryIndexHandler *)inHandler
{
	return [self initWithSetup:inSetup handler:inHandler versionTag:nil options:nil];
}

- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)inSetup
            handler:(YapDatabaseSecondaryIndexHandler *)inHandler
         versionTag:(NSString *)inVersionTag
{
	return [self initWithSetup:inSetup handler:inHandler versionTag:inVersionTag options:nil];
}

- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)inSetup
            handler:(YapDatabaseSecondaryIndexHandler *)inHandler
         versionTag:(NSString *)inVersionTag
            options:(YapDatabaseSecondaryIndexOptions *)inOptions
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
	
	if (inHandler == NULL)
	{
		NSAssert(NO, @"Invalid handler: NULL");
		
		YDBLogError(@"%@: Invalid handler: NULL", THIS_METHOD);
		return nil;
	}
	
	// Looks sane, proceed with normal init
	
	if ((self = [super init]))
	{
		setup = [inSetup copy];
		handler = inHandler;
		
		columnNamesSharedKeySet = [NSDictionary sharedKeySetForKeys:[setup columnNames]];
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseSecondaryIndexOptions alloc] init];
	}
	return self;
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseSecondaryIndexConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

- (NSString *)tableName
{
	return [[self class] tableNameForRegisteredName:self.registeredName];
}

@end
