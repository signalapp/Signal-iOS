#import "YapDatabaseActionManagerConnection.h"
#import "YapDatabaseActionManagerPrivate.h"


@implementation YapDatabaseActionManagerConnection

- (id)initWithView:(YapDatabaseView *)inView databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super initWithView:inView databaseConnection:inDbC]))
	{
		actionItemsCache = [[YapCache alloc] initWithCountLimit:100];
		actionItemsCache.allowedKeyClasses = [NSSet setWithObject:[YapCollectionKey class]];
		actionItemsCache.allowedObjectClasses = [NSSet setWithObjects:[NSArray class], [NSNull class], nil];
	}
	return self;
}

- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseActionManagerTransaction *extTransaction =
	  [[YapDatabaseActionManagerTransaction alloc] initWithViewConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	return extTransaction;
}

- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseActionManagerTransaction *extTransaction =
	  [[YapDatabaseActionManagerTransaction alloc] initWithViewConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return extTransaction;
}

- (void)postRollbackCleanup
{
	[actionItemsCache removeAllObjects];
	[super postRollbackCleanup];
}

@end
