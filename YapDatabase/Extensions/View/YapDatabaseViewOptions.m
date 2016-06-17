#import "YapDatabaseViewOptions.h"


@implementation YapDatabaseViewOptions

@synthesize isPersistent = isPersistent;
@synthesize allowedCollections = allowedCollections;
@synthesize skipInitialViewPopulation = skipInitialViewPopulation;

- (id)init
{
	if ((self = [super init]))
	{
		isPersistent = YES;
	}
	return self;
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseViewOptions *copy = [[[self class] alloc] init]; // [self class] required to support subclassing
	copy->isPersistent = isPersistent;
	copy->allowedCollections = allowedCollections;
	copy->skipInitialViewPopulation = skipInitialViewPopulation;

	return copy;
}

@end
