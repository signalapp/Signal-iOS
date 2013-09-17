#import "YapDatabaseFullTextSearchSnippetOptions.h"


@implementation YapDatabaseFullTextSearchSnippetOptions

@synthesize startMatchText = startMatchText;
@synthesize endMatchText = endMatchText;
@synthesize ellipsesText = ellipsesText;
@synthesize columnName = columnName;
@synthesize numberOfTokens = numberOfTokens;

- (id)init
{
	if ((self = [super init]))
	{
		startMatchText = @"<b>";
		endMatchText = @"</b>";
		ellipsesText = @"…";
		
		numberOfTokens = 15;
	}
	return self;
}

- (id)initForCopy
{
	if ((self = [super init]))
	{
		// copyWithZone will fill out values for us
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseFullTextSearchSnippetOptions *copy = [[YapDatabaseFullTextSearchSnippetOptions alloc] init];
	
	copy->startMatchText = startMatchText;
	copy->endMatchText = endMatchText;
	copy->ellipsesText = ellipsesText;
	copy->columnName = columnName;
	copy->numberOfTokens = numberOfTokens;
	
	return copy;
}

@end
