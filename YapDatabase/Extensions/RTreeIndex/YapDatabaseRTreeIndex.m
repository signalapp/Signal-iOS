#import "YapDatabaseRTreeIndex.h"
#import "YapDatabaseRTreeIndexPrivate.h"

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


@implementation YapDatabaseRTreeIndex

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
    return @[ @"YapCollectionsDatabaseRTreeIndex" ];
}

+ (NSString *)tableNameForRegisteredName:(NSString *)registeredName
{
    return [NSString stringWithFormat:@"rTreeIndex_%@", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@dynamic setup;

- (YapDatabaseRTreeIndexSetup *)setup
{
	return [setup copy]; // Our instance must remain immutable
}

@synthesize handler = handler;
@synthesize versionTag = versionTag;

- (id)init
{
    NSAssert(NO, @"Must use designated initializer");
    return nil;
}

- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)inSetup
            handler:(YapDatabaseRTreeIndexHandler *)inHandler
{
    return [self initWithSetup:inSetup handler:inHandler versionTag:nil options:nil];
}

- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)inSetup
            handler:(YapDatabaseRTreeIndexHandler *)inHandler
         versionTag:(NSString *)inVersionTag
{
    return [self initWithSetup:inSetup handler:inHandler versionTag:inVersionTag options:nil];
}

- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)inSetup
            handler:(YapDatabaseRTreeIndexHandler *)inHandler
         versionTag:(NSString *)inVersionTag
            options:(YapDatabaseRTreeIndexOptions *)inOptions
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
		handler = inHandler;
        setup = [inSetup copy];

        columnNamesSharedKeySet = [NSDictionary sharedKeySetForKeys:[setup columnNames]];

        versionTag = inVersionTag ? [inVersionTag copy] : @"";

        options = inOptions ? [inOptions copy] : [[YapDatabaseRTreeIndexOptions alloc] init];
    }
    return self;
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
    return [[YapDatabaseRTreeIndexConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

- (NSString *)tableName
{
    return [[self class] tableNameForRegisteredName:self.registeredName];
}

@end
