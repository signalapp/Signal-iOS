#import "YapDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapDatabaseView

@synthesize filterBlock;
@synthesize sortBlock;

@synthesize filterBlockType;
@synthesize sortBlockType;

- (id)initWithFilterBlock:(YapDatabaseViewFilterBlock)inFilterBlock
               filterType:(YapDatabaseViewBlockType)inFilterBlockType
                sortBlock:(YapDatabaseViewSortBlock)inSortBlock
                 sortType:(YapDatabaseViewBlockType)inSortBlockType
{
	if ((self = [super init]))
	{
		filterBlock = inFilterBlock;
		filterBlockType = inFilterBlockType;
		
		sortBlock = inSortBlock;
		sortBlockType = inSortBlockType;
	}
	return self;
}

- (YapAbstractDatabaseViewConnection *)newConnection
{
	return [[YapDatabaseViewConnection alloc] initWithDatabaseView:self];
}

/*
- (BOOL)databaseTableExists
{
	// Is this method needed ?
	
	BOOL result = NO;
	
	NSString *tableName = [abstractViewConnection->abstractView tableName];
	
	NSString *query = [NSString stringWithFormat:
					   @"SELECT COUNT(*) AS NumberOfRows FROM sqlite_master"
					   @" WHERE type='table' AND name='%@'", tableName];
	
	sqlite3 *db = databaseTransaction->abstractConnection->db;
	sqlite3_stmt *statement;
	int status;
	
	status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"Error creating query statement! %d %s", status, sqlite3_errmsg(db));
		return NO;
	}
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (sqlite3_column_int64(statement, 0) > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing statement: %d %s", status, sqlite3_errmsg(db));
	}
	
	return result;
}
*/

@end
