/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreOptions.h"


@implementation YapDatabaseCloudCoreOptions

@synthesize allowedCollections = allowedCollections;
@synthesize allowedOperationClasses = allowedOperationClasses;
@synthesize enableAttachDetachSupport = enableAttachDetachSupport;
@synthesize implicitAttach = implicitAttach;
@synthesize enableTagSupport = enableTagSupport;


- (instancetype)init
{
	if ((self = [super init]))
	{
		enableAttachDetachSupport = YES;
		implicitAttach = YES;
		enableTagSupport = YES;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudCoreOptions *copy = [[[self class] alloc] init]; // [self class] required to support subclassing
	copy->allowedCollections = allowedCollections;
	copy->allowedOperationClasses = allowedOperationClasses;
	copy->enableAttachDetachSupport = enableAttachDetachSupport;
	copy->implicitAttach = implicitAttach;
	copy->enableTagSupport = enableTagSupport;
	
	return copy;
}

@end
