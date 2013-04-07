#import "YapAbstractDatabaseViewTransaction.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseViewTransaction

- (id)initWithConnection:(YapAbstractDatabaseConnection *)inConnection
         readTransaction:(YapAbstractDatabaseTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		connection = inConnection;
		readTransaction = inTransaction;
	}
	return self;
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)inConnection
    readWriteTransaction:(YapAbstractDatabaseTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		connection = inConnection;
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
	connection = nil;
	readTransaction = nil;
	readWriteTransaction = nil;
}

@end
