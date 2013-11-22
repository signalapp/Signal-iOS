#import "YapCollectionsDatabaseFilteredViewConnection.h"
#import "YapCollectionsDatabaseFilteredViewPrivate.h"


@implementation YapCollectionsDatabaseFilteredViewConnection

- (YapCollectionsDatabaseFilteredView *)filteredView
{
	return (YapCollectionsDatabaseFilteredView *)view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *dbTransaction =
	  (YapCollectionsDatabaseReadTransaction *)databaseTransaction;
	
	YapCollectionsDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapCollectionsDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                            databaseTransaction:dbTransaction];
	
	return filteredViewTransaction;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	__unsafe_unretained YapCollectionsDatabaseReadTransaction *dbTransaction =
	  (YapCollectionsDatabaseReadTransaction *)databaseTransaction;
	
	YapCollectionsDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapCollectionsDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                            databaseTransaction:dbTransaction];
	
	[self prepareForReadWriteTransaction];
	return filteredViewTransaction;
}

@end
