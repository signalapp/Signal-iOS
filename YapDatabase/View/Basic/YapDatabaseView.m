#import "YapDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"

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
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_VERBOSE;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseView

+ (BOOL)createTablesForRegisteredName:(NSString *)registeredName
                             database:(YapAbstractDatabase *)database
                               sqlite:(sqlite3 *)db
                                error:(NSError **)errorPtr
{
	NSLog(@"database: %@", database);
	NSLog(@"? = %@", ([database isKindOfClass:[YapDatabase class]] ? @"YES" : @"NO"));
	NSLog(@"? = %@", ([database isKindOfClass:[YapAbstractDatabase class]] ? @"YES" : @"NO"));
	
//	if (![database isKindOfClass:[YapDatabase class]])
//	{
//		if (errorPtr)
//		{
//			NSDictionary *userInfo = @{
//				NSLocalizedDescriptionKey: @"YapDatabaseView only supports YapDatabase, not YapCollectionsDatabase" };
//			
//			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:501 userInfo:userInfo];
//		}
//		return NO;
//	}
	
	NSString *keyTableName = [self keyTableNameForRegisteredName:registeredName];
	NSString *pageTableName = [self pageTableNameForRegisteredName:registeredName];
	
	YDBLogVerbose(@"Creating view tables for registeredName(%@): %@, %@", registeredName, keyTableName, pageTableName);
	
	NSString *createKeyTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"key\" CHAR NOT NULL PRIMARY KEY,"
	    @"  \"pageKey\" CHAR NOT NULL"
	    @" );", keyTableName];
	
	NSString *createPageTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"pageKey\" CHAR NOT NULL PRIMARY KEY,"
	    @"  \"data\" BLOB,"
		@"  \"metadata\" BLOB"
	    @" );", pageTableName];
	
	int status;
	
	status = sqlite3_exec(db, [createKeyTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating key table (%@): %d %s",
		            THIS_METHOD, keyTableName, status, sqlite3_errmsg(db));
		
		if (errorPtr)
		{
			NSDictionary *userInfo = @{
			    NSLocalizedDescriptionKey : @"Error creating key table",
				@"sqlite3_status" : @(status),
				@"sqlite3_errmsg" : [NSString stringWithFormat:@"%s", sqlite3_errmsg(db)]
			};
			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:500 userInfo:userInfo];
		}
		return NO;
	}
	
	status = sqlite3_exec(db, [createPageTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating page table (%@): %d %s",
		            THIS_METHOD, pageTableName, status, sqlite3_errmsg(db));
		if (errorPtr)
		{
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey : @"Error creating page table",
				@"sqlite3_status" : @(status),
				@"sqlite3_errmsg" : [NSString stringWithFormat:@"%s", sqlite3_errmsg(db)]
			};
			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:500 userInfo:userInfo];
		}
		return NO;
	}
	
	return YES;
}

+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db
                              error:(NSError **)errorPtr
{
	if (![database isKindOfClass:[YapDatabase class]])
	{
		if (errorPtr)
		{
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey: @"YapDatabaseView only supports YapDatabase, not YapCollectionsDatabase" };
			
			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:501 userInfo:userInfo];
		}
		return NO;
	}
	
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
		if (errorPtr)
		{
			NSDictionary *userInfo = @{
			    NSLocalizedDescriptionKey : @"Error dropping key table",
				@"sqlite3_status" : @(status),
				@"sqlite3_errmsg" : [NSString stringWithFormat:@"%s", sqlite3_errmsg(db)]
			};
			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:500 userInfo:userInfo];
		}
		return NO;
	}
	
	status = sqlite3_exec(db, [dropPageTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping page table (%@): %d %s",
		            THIS_METHOD, pageTableName, status, sqlite3_errmsg(db));
		if (errorPtr)
		{
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey : @"Error dropping page table",
				@"sqlite3_status" : @(status),
				@"sqlite3_errmsg" : [NSString stringWithFormat:@"%s", sqlite3_errmsg(db)]
			};
			*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:500 userInfo:userInfo];
		}
		return NO;
	}
	
	return YES;
}

+ (NSString *)keyTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_key", registeredName];
}

+ (NSString *)pageTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_page", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize groupingBlock;
@synthesize sortingBlock;

@synthesize groupingBlockType;
@synthesize sortingBlockType;

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
{
	if ((self = [super init]))
	{
		groupingBlock = inGroupingBlock;
		groupingBlockType = inGroupingBlockType;
		
		sortingBlock = inSortingBlock;
		sortingBlockType = inSortingBlockType;
	}
	return self;
}

- (YapAbstractDatabaseViewConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseViewConnection alloc] initWithView:self databaseConnection:databaseConnection];
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
