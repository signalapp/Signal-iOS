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
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (void)_flushMemoryWithLevel:(int)level
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

- (void)postRollbackCleanup
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr externalChangeset:(NSMutableDictionary **)externalPtr
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	*internalPtr = nil;
	*externalPtr = nil;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

@end
