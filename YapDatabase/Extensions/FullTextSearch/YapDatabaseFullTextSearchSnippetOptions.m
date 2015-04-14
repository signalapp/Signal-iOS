#import "YapDatabaseFullTextSearchSnippetOptions.h"


@implementation YapDatabaseFullTextSearchSnippetOptions

+ (NSString *)defaultStartMatchText {
	return @"<b>";
}

+ (NSString *)defaultEndMatchText {
	return @"</b>";
}

+ (NSString *)defaultEllipsesText {
	return @"...";
}

+ (int)defaultNumberOfTokens {
	return 15;
}

@synthesize startMatchText = startMatchText;
@synthesize endMatchText = endMatchText;
@synthesize ellipsesText = ellipsesText;
@synthesize columnName = columnName;
@synthesize numberOfTokens = numberOfTokens;

- (id)init
{
	if ((self = [super init]))
	{
		startMatchText = [[self class] defaultStartMatchText];
		endMatchText = [[self class] defaultEndMatchText];
		ellipsesText = [[self class] defaultEllipsesText];
		
		numberOfTokens = [[self class] defaultNumberOfTokens];
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

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseFullTextSearchSnippetOptions *copy = [[YapDatabaseFullTextSearchSnippetOptions alloc] initForCopy];
	
	copy->startMatchText = startMatchText;
	copy->endMatchText = endMatchText;
	copy->ellipsesText = ellipsesText;
	copy->columnName = columnName;
	copy->numberOfTokens = numberOfTokens;
	
	return copy;
}

- (void)setStartMatchText:(NSString *)text
{
	if (text)
		startMatchText = [text copy];
	else
		startMatchText = [[self class] defaultStartMatchText];
}

- (void)setEndMatchText:(NSString *)text
{
	if (text)
		endMatchText = [text copy];
	else
		endMatchText = [[self class] defaultEndMatchText];
}

- (void)setEllipsesText:(NSString *)text
{
	if (text)
		ellipsesText = [text copy];
	else
		ellipsesText = [[self class] defaultEllipsesText];
}

- (void)setNumberOfTokens:(int)count
{
	if (count != 0)
		numberOfTokens = count;
	else
		numberOfTokens = [[self class] defaultNumberOfTokens];
}

@end
