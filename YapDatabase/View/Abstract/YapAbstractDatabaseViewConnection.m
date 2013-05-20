#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseViewConnection

@synthesize abstractView = abstractView;

- (id)initWithView:(YapAbstractDatabaseView *)view databaseConnection:(YapAbstractDatabaseConnection *)connection
{
	if ((self = [super init]))
	{
		abstractView = view;
		databaseConnection = connection;
	}
	return self;
}

- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

- (void)postRollbackCleanup
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (NSMutableDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method in subclass");
}

@end
