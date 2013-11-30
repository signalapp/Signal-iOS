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
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	__unsafe_unretained YapDatabaseReadTransaction *dbTransaction =
	  (YapDatabaseReadTransaction *)databaseTransaction;
	
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:dbTransaction];
	
	return filteredViewTransaction;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	__unsafe_unretained YapDatabaseReadTransaction *dbTransaction =
	  (YapDatabaseReadTransaction *)databaseTransaction;
	
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:dbTransaction];
	
	[self prepareForReadWriteTransaction];
	return filteredViewTransaction;
}

@end
