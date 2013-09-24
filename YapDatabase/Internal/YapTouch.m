#import "YapTouch.h"


@implementation YapTouch

static YapTouch *singleton;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		singleton = [[YapTouch alloc] init];
	}
}

+ (id)touch
{
	return singleton;
}

- (id)init
{
	NSAssert(singleton == nil, @"Must use singleton via [YapTouch touch]");
	
	self = [super init];
	return self;
}

@end
