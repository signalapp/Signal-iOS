#import "YapAbstractDatabaseExtensionConnection.h"
#import "YapAbstractDatabaseExtensionPrivate.h"


@implementation YapAbstractDatabaseExtensionConnection

@synthesize abstractExtension = extension;

- (id)initWithExtension:(YapAbstractDatabaseExtension *)inExtension
     databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super init]))
	{
		extension = inExtension;
		databaseConnection = inDatabaseConnection;
	}
	return self;
}

- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

- (void)postRollbackCleanup
{
	NSAssert(NO, @"Missing required override method in subclass");
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr externalChangeset:(NSMutableDictionary **)externalPtr
{
	NSAssert(NO, @"Missing required override method in subclass");
	
	*internalPtr = nil;
	*externalPtr = nil;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method in subclass");
}

@end
