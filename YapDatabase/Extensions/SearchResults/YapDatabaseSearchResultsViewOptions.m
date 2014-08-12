#import "YapDatabaseSearchResultsViewOptions.h"


@implementation YapDatabaseSearchResultsViewOptions

@synthesize allowedGroups = allowedGroups;
@synthesize snippetOptions = snippetOptions;

- (id)init
{
	if ((self = [super init]))
	{
		self.isPersistent = NO; // <<-- This is changed for YapDatabaseSearchResultsOptions
	}
	return self;
}

- (YapDatabaseFullTextSearchSnippetOptions *)snippetOptions
{
	// The internal snippetOptions ivar MUST remain immutable.
	// So we MUST return a copy.
	return [snippetOptions copy]; // <- Do NOT change
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseSearchResultsViewOptions *copy = [super copyWithZone:zone];
	
	copy->allowedGroups = allowedGroups;
	copy->snippetOptions = snippetOptions;
	
	return copy;
}

@end
