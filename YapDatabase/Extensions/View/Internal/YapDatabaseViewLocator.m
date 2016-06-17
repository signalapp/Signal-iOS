#import "YapDatabaseViewLocator.h"


@implementation YapDatabaseViewLocator

@synthesize group = group;
@synthesize index = index;
@synthesize pageKey = pageKey;

- (instancetype)initWithGroup:(NSString *)inGroup index:(NSUInteger)inIndex
{
	return [self initWithGroup:inGroup index:inIndex pageKey:nil];
}

- (instancetype)initWithGroup:(NSString *)inGroup index:(NSUInteger)inIndex pageKey:(NSString *)inPageKey
{
	if ((self = [super init]))
	{
		group = [inGroup copy];
		index = inIndex;
		pageKey = [inPageKey copy];
	}
	return self;
}

@end
