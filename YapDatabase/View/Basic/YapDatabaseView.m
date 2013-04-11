#import "YapDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapDatabaseView

@synthesize filterBlock;
@synthesize sortBlock;

@synthesize filterBlockType;
@synthesize sortBlockType;

- (id)initWithFilterBlock:(YapDatabaseViewFilterBlock)inFilterBlock
               filterType:(YapDatabaseViewBlockType)inFilterBlockType
                sortBlock:(YapDatabaseViewSortBlock)inSortBlock
                 sortType:(YapDatabaseViewBlockType)inSortBlockType
{
	if ((self = [super init]))
	{
		filterBlock = inFilterBlock;
		filterBlockType = inFilterBlockType;
		
		sortBlock = inSortBlock;
		sortBlockType = inSortBlockType;
	}
	return self;
}

- (YapAbstractDatabaseViewConnection *)newConnection
{
	return [[YapDatabaseViewConnection alloc] initWithDatabaseView:self];
}

@end
