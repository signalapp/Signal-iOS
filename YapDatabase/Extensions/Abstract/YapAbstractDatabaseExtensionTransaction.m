#import "YapAbstractDatabaseExtensionTransaction.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"


@implementation YapAbstractDatabaseExtensionTransaction

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
	NSAssert(NO, @"Missing required override method in subclass");
}

@end
