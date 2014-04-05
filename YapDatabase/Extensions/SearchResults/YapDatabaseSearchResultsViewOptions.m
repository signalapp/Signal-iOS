#import "YapDatabaseSearchResultsViewOptions.h"


@implementation YapDatabaseSearchResultsViewOptions

- (id)init
{
	if ((self = [super init]))
	{
		self.isPersistent = NO; // <<-- This is changed for YapDatabaseSearchResultsOptions
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseSearchResultsViewOptions *copy = [super copyWithZone:zone];
	return copy;
}

@end
