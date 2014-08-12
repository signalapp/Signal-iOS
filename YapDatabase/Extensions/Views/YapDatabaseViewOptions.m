#import "YapDatabaseViewOptions.h"


@implementation YapDatabaseViewOptions

@synthesize isPersistent = isPersistent;
@synthesize allowedCollections = allowedCollections;

- (id)init
{
	if ((self = [super init]))
	{
		isPersistent = YES;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewOptions *copy = [[[self class] alloc] init]; // [self class] required to support subclassing
	copy->isPersistent = isPersistent;
	copy->allowedCollections = allowedCollections;
	
	return copy;
}

@end
