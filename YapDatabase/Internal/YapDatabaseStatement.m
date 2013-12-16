#import "YapDatabaseStatement.h"
#import "YapDatabasePrivate.h"


@implementation YapDatabaseStatement
{
	sqlite3_stmt *stmt;
}

@synthesize stmt = stmt;

- (id)initWithStatement:(sqlite3_stmt *)inStmt
{
	if ((self = [super init]))
	{
		stmt = inStmt;
	}
	return self;
}

- (void)dealloc
{
	sqlite_finalize_null(&stmt);
}

@end
