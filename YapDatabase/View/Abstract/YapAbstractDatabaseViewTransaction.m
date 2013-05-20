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

/**
 * See YapAbstractDatabaseViewPrivate for discussion of this method.
**/
- (BOOL)prepareIfNeeded
{
	NSAssert(NO, @"Missing required override method in subclass");
	return NO;
}

/**
 * Subclasses should invoke [super commitTransaction] at the END of their implementation.
**/
- (void)commitTransaction
{
	// A viewTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the view in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this method is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	abstractViewConnection = nil; // Do not remove !
	databaseTransaction = nil;    // Do not remove !
}

@end
