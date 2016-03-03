#import "YapMutationStack.h"


@interface YapMutationStackItem_Abstract (/* Private */) {
@public
	__strong YapMutationStack_Abstract *parent;
	__strong YapMutationStackItem_Abstract *below;
}
- (instancetype)initWithParent:(YapMutationStack_Abstract *)inParent below:(YapMutationStackItem_Abstract *)inBelow;
@end



@implementation YapMutationStack_Abstract {
@protected
	
	__weak YapMutationStackItem_Abstract *weak_top;
}

- (instancetype)init
{
	self = [super init];
	return self;
}

- (void)clear
{
	weak_top = nil;
}

- (void)pop:(YapMutationStackItem_Abstract *)item
{
	__strong YapMutationStackItem_Abstract *top = weak_top;
	if (top && (top == item))
	{
		weak_top = item->below;
	}
}

@end



@implementation YapMutationStackItem_Abstract

- (instancetype)initWithParent:(YapMutationStack_Abstract *)inParent below:(YapMutationStackItem_Abstract *)inBelow
{
	if ((self = [super init]))
	{
		parent = inParent;
		below = inBelow;
	}
	return self;
}

- (void)dealloc
{
	[parent pop:self];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapMutationStackItem_Bool (/* Private */) {
@public
	BOOL isMutated;
}
@end



@implementation YapMutationStack_Bool

- (YapMutationStackItem_Bool *)push
{
	YapMutationStackItem_Bool *item = [[YapMutationStackItem_Bool alloc] initWithParent:self below:weak_top];
	
	weak_top = item;
	return item;
}

- (void)markAsMutated
{
	__strong YapMutationStackItem_Abstract *item = weak_top;
	while (item)
	{
		((YapMutationStackItem_Bool *)item)->isMutated = YES;
		item = item->below;
	}
}

@end



@implementation YapMutationStackItem_Bool

@synthesize isMutated = isMutated;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapMutationStackItem_Set (/* Private */) {
@public
	NSMutableSet *set;
}
@end



@implementation YapMutationStack_Set

- (YapMutationStackItem_Set *)push
{
	YapMutationStackItem_Set *item = [[YapMutationStackItem_Set alloc] initWithParent:self below:weak_top];
	
	weak_top = item;
	return item;
}

- (void)markAsMutated:(id)object
{
	__strong YapMutationStackItem_Abstract *top = weak_top;
	while (top)
	{
		[((YapMutationStackItem_Set *)top)->set addObject:object];
		top = top->below;
	}
}
	
@end



@implementation YapMutationStackItem_Set

- (BOOL)isMutated:(id)object
{
	return [set containsObject:object];
}

@end
