#import "YapProxyObject.h"
#import "YapProxyObjectPrivate.h"

#import "YapCollectionKey.h"
#import "YapDatabasePrivate.h"


@implementation YapProxyObject
{
	id realObject;
	
	BOOL isMetadata;
	int64_t rowid;
	YapCollectionKey *collectionKey;
	YapDatabaseReadTransaction *transaction;
}

@dynamic isRealObjectLoaded;
@dynamic realObject;

- (BOOL)isRealObjectLoaded
{
	return (realObject != nil);
}

- (id)realObject
{
	if ((realObject == nil) && (collectionKey != nil))
	{
		if (isMetadata)
			realObject = [transaction metadataForCollectionKey:collectionKey withRowid:rowid];
		else
			realObject = [transaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	return realObject;
}

- (void)reset
{
	realObject = nil;
	collectionKey = nil;
	transaction = nil;
}

- (void)resetWithRealObject:(id)inRealObject
{
	realObject = inRealObject;
	
	collectionKey = nil;
	transaction = nil;
}

- (void)resetWithRowid:(int64_t)inRowid
         collectionKey:(YapCollectionKey *)inCollectionKey
            isMetadata:(BOOL)inIsMetadata
           transaction:(YapDatabaseReadTransaction *)inTransaction
{
	realObject = nil;
	
	rowid = inRowid;
	collectionKey = inCollectionKey;
	isMetadata = inIsMetadata;
	transaction = inTransaction;
}

/**
 * From Apple's documentation:
 *
 * > NSProxy implements the basic methods required of a root class, including those defined in the NSObject protocol.
 * > However, as an abstract class it doesn’t provide an initialization method, and it raises an exception upon
 * > receiving any message it doesn’t respond to. A concrete subclass must therefore provide an initialization or
 * > creation method and override the forwardInvocation: and methodSignatureForSelector: methods to handle messages
 * > that it doesn’t implement itself. A subclass’s implementation of forwardInvocation: should do whatever is needed
 * > to process the invocation, such as forwarding the invocation over the network or loading the real object and
 * > passing it the invocation. methodSignatureForSelector: is required to provide argument type information for a
 * > given message; a subclass’s implementation should be able to determine the argument types for the messages it
 * > needs to forward and should construct an NSMethodSignature object accordingly.
**/

- (instancetype)init
{
	// Don't call [super init], as NSProxy does not recognize -init.
	
	return self;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	[anInvocation setTarget:self.realObject];
	[anInvocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
	return [self.realObject methodSignatureForSelector:aSelector];
}

@end
