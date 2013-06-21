#import "YapAbstractDatabaseExtensionTransaction.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"


@implementation YapAbstractDatabaseExtensionTransaction

- (id)initWithExtensionConnection:(YapAbstractDatabaseExtensionConnection *)inExtensionConnection
              databaseTransaction:(YapAbstractDatabaseTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		extensionConnection = inExtensionConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

/**
 * See YapAbstractDatabaseExtensionPrivate for discussion of this method.
**/
- (BOOL)prepareIfNeeded
{
	NSAssert(NO, @"Missing required override method in subclass");
	return NO;
}

/**
 * This method is called if within a readwrite transaction.
 * This method is optional.
**/
- (void)preCommitTransaction
{
	// Subclasses may optionally override this method to perform any "cleanup" before the changesets are requested.
	// Remember, the changesets are requested before the commitTransaction method is invoked.
}

/**
 * Subclasses should invoke [super commitTransaction] at the END of their implementation.
**/
- (void)commitTransaction
{
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this method is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	extensionConnection = nil; // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

@end
