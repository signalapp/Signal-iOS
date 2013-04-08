#import "YapAbstractDatabaseViewTransaction.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseViewTransaction

- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)inViewConnection
          databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
         readTransaction:(YapAbstractDatabaseTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		viewConnection = inViewConnection;
		databaseConnection = inDatabaseConnection;
		readTransaction = inTransaction;
	}
	return self;
}

- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)inViewConnection
          databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
        readWriteTransaction:(YapAbstractDatabaseTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		viewConnection = inViewConnection;
		databaseConnection = inDatabaseConnection;
		readTransaction = inTransaction;
		readWriteTransaction = inTransaction;
	}
	return self;
}

- (void)handleInsertKey:(NSString *)key withObject:(id)object metadata:(id)metadata
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)handleUpdateKey:(NSString *)key withObject:(id)object metadata:(id)metadata
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)handleUpdateKey:(NSString *)key withMetadata:(id)metadata
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)handleRemoveKey:(NSString *)key
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)handleRemoveAllKeys
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)commitTransaction
{
	viewConnection = nil;
	databaseConnection = nil;
	readTransaction = nil;
	readWriteTransaction = nil;
}

@end
