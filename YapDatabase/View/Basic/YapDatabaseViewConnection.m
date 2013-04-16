#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewPrivate.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCache.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseViewConnection

- (id)initWithDatabaseView:(YapAbstractDatabaseView *)parent
{
	if ((self = [super initWithDatabaseView:parent]))
	{
		keyCache = [[YapCache alloc] init];
		pageCache = [[YapCache alloc] init];
	}
	return self;
}

/**
 * Required override method from YapAbstractDatabaseViewConnection.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapDatabaseViewTransaction alloc] initWithViewConnection:self
	                                              databaseTransaction:databaseTransaction];
}

- (BOOL)isOpen
{
	return (sectionPagesDict != nil);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)getDataForKeyStatement
{
	if (getDataForKeyStatement == NULL)
	{
		NSString *statement = [NSString stringWithFormat:
		    @"SELECT \"data\" FROM \"%@\" WHERE \"type\" = ? AND \"key\" = ?;", [abstractView tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [statement UTF8String], -1, &getDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating '%@': %d %s", THIS_FILE, THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return getDataForKeyStatement;
}

@end
