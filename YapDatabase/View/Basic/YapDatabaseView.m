#import "YapDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapDatabaseView

@synthesize filterBlock;
@synthesize sortBlock;

@synthesize filterBlockType;
@synthesize sortBlockType;

- (id)initWithName:(NSString *)inName
       filterBlock:(YapDatabaseViewFilterBlock)inFilterBlock
        filterType:(YapDatabaseViewBlockType)inFilterBlockType
         sortBlock:(YapDatabaseViewSortBlock)inSortBlock
          sortType:(YapDatabaseViewBlockType)inSortBlockType
{
	if ((self = [super init]))
	{
		name = [inName copy];
		
		filterBlock = inFilterBlock;
		filterBlockType = inFilterBlockType;
		
		sortBlock = inSortBlock;
		sortBlockType = inSortBlockType;
	}
	return self;
}

@end
