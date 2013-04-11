#import "YapAbstractDatabaseViewTransaction.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapAbstractDatabasePrivate.h"


@implementation YapAbstractDatabaseViewTransaction

- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)inViewConnection
         databaseTransaction:(YapAbstractDatabaseTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		abstractViewConnection = inViewConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

- (BOOL)open
{
	NSAssert(NO, @"Missing required override method in subclass");
	
	return NO;
}

- (BOOL)createOrOpen
{
	NSAssert(NO, @"Missing required override method in subclass");
	
	return NO;
}

- (void)commitTransaction
{
	abstractViewConnection = nil;
	databaseTransaction = nil;
}

@end
