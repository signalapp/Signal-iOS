/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreOptions.h"


@implementation YapDatabaseCloudCoreOptions

@synthesize allowedOperationClasses = allowedOperationClasses;
@synthesize enableAttachDetachSupport = enableAttachDetachSupport;
@synthesize enableTagSupport = enableTagSupport;


- (instancetype)init
{
	if ((self = [super init]))
	{
		enableAttachDetachSupport = NO;
		enableTagSupport = NO;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudCoreOptions *copy = [[[self class] alloc] init]; // [self class] required to support subclassing
	copy->allowedOperationClasses = allowedOperationClasses;
	copy->enableAttachDetachSupport = enableAttachDetachSupport;
	copy->enableTagSupport = enableTagSupport;
	
	return copy;
}

@end
