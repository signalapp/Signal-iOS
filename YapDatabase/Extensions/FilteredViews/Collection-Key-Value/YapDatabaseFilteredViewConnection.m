#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewPrivate.h"


@implementation YapDatabaseFilteredViewConnection

- (YapDatabaseFilteredView *)filteredView
{
	return (YapDatabaseFilteredView *)view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:databaseTransaction];
	
	return filteredViewTransaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return filteredViewTransaction;
}

@end
