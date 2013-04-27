#import "YapDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapDatabaseView

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

- (YapAbstractDatabaseViewConnection *)newConnection
{
	return [[YapDatabaseViewConnection alloc] initWithDatabaseView:self];
}

- (NSString *)keyTableName
{
	return [NSString stringWithFormat:@"view_%@_key", self.registeredName];
}

- (NSString *)pageTableName
{
	return [NSString stringWithFormat:@"view_%@_page", self.registeredName];
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
