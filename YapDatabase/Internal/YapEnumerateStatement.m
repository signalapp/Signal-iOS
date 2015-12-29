#import "YapEnumerateStatement.h"
#import "YapDatabaseString.h"


@interface YapEnumerateStatement ()
- (instancetype)initWithFactory:(YapEnumerateStatementFactory *)factory stmt:(sqlite3_stmt *)stmt;
@end

@implementation YapEnumerateStatementFactory
{
	sqlite3 *db;
	sqlite3_stmt *stmt;
	
	NSString *stmtString;
}

- (instancetype)initWithDb:(sqlite3 *)inDb statement:(NSString *)inStmtString
{
	NSParameterAssert(inDb != NULL);
	NSParameterAssert(inStmtString != nil);
	
	if ((self = [super init]))
	{
		db = inDb;
		stmtString = [inStmtString copy];
	}
	return self;
}

- (void)dealloc
{
	if (stmt)
	{
		sqlite3_finalize(stmt);
		stmt = NULL;
	}
}

- (YapEnumerateStatement *)newStatement:(int *)statusPtr
{
	if (stmt) // use recycled stmt
	{
		YapEnumerateStatement *result = [[YapEnumerateStatement alloc] initWithFactory:self stmt:stmt];
		stmt = NULL;
		
		if (statusPtr) *statusPtr = SQLITE_OK;
		return result;
	}
	else // create new stmt
	{
		YapEnumerateStatement *result = nil;
		
		YapDatabaseString stmtStr; MakeYapDatabaseString(&stmtStr, stmtString);
		
		sqlite3_stmt *newStmt = NULL;
		int status = sqlite3_prepare_v2(db, stmtStr.str, stmtStr.length+1, &newStmt, NULL);
		if (status == SQLITE_OK)
		{
			result = [[YapEnumerateStatement alloc] initWithFactory:self stmt:newStmt];
		}
		
		FreeYapDatabaseString(&stmtStr);
		
		if (statusPtr) *statusPtr = status;
		return result;
	}
}

- (BOOL)recycle:(sqlite3_stmt *)inStmt
{
	if (stmt == NULL)
	{
		stmt = inStmt;
		return YES;
	}
	
	return NO;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapEnumerateStatement
{
	__strong YapEnumerateStatementFactory *factory;
}

@synthesize statement = stmt;

- (instancetype)initWithFactory:(YapEnumerateStatementFactory *)inFactory stmt:(sqlite3_stmt *)inStmt
{
	NSParameterAssert(inFactory != nil);
	NSParameterAssert(inStmt != NULL);
	
	if ((self = [super init]))
	{
		factory = inFactory;
		stmt = inStmt;
	}
	return self;
}

- (void)dealloc
{
	sqlite3_clear_bindings(stmt);
	sqlite3_reset(stmt);
	
	if (![factory recycle:stmt])
	{
		sqlite3_finalize(stmt);
		stmt = NULL;
	}
}

@end
