#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionPrivate.h"


@implementation YapDatabaseExtensionConnection

- (YapDatabaseExtension *)extension
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr
           externalChangeset:(NSMutableDictionary **)externalPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	*internalPtr = nil;
	*externalPtr = nil;
	*hasDiskChangesPtr = NO;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

@end
