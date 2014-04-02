#import "YapDatabaseSearchResultsOptions.h"


@implementation YapDatabaseSearchResultsOptions

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
	YapDatabaseSearchResultsOptions *copy = [super copyWithZone:zone];
	return copy;
}

@end
