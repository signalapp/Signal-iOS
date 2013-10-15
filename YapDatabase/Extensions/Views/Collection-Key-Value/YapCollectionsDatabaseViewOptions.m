#import "YapCollectionsDatabaseViewOptions.h"


@implementation YapCollectionsDatabaseViewOptions

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
	YapCollectionsDatabaseViewOptions *copy = [[YapCollectionsDatabaseViewOptions alloc] init];
	copy->isPersistent = isPersistent;
	copy->allowedCollections = allowedCollections;
	
	return copy;
}

@end
