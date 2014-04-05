#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewPrivate.h"


@implementation YapDatabaseSearchResultsViewConnection

- (YapDatabaseSearchResultsView *)searchResultsView
{
	return (YapDatabaseSearchResultsView *)view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsViewTransaction *transaction =
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithViewConnection:self
	                                                      databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsViewTransaction *transaction =
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithViewConnection:self
	                                                      databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

@end
