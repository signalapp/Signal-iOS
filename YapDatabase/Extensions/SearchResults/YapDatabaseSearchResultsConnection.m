#import "YapDatabaseSearchResultsConnection.h"
#import "YapDatabaseSearchResultsPrivate.h"


@implementation YapDatabaseSearchResultsConnection

- (YapDatabaseSearchResults *)searchResults
{
	return (YapDatabaseSearchResults *)view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsTransaction *transaction =
	  [[YapDatabaseSearchResultsTransaction alloc] initWithViewConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsTransaction *transaction =
	  [[YapDatabaseSearchResultsTransaction alloc] initWithViewConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

@end
