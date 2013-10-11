#import "YapDatabaseViewOptions.h"


@implementation YapDatabaseViewOptions

@synthesize isPersistent = isPersistent;

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
	YapDatabaseViewOptions *copy = [[YapDatabaseViewOptions alloc] init];
	copy->isPersistent = isPersistent;
	
	return copy;
}

@end
