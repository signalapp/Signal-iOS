#import "TodoTextView.h"


@implementation TodoTextView

@synthesize needsScrollIfNeeded;

- (CGSize)intrinsicContentSize
{
	CGSize maxSize = self.frame.size;
	maxSize.height = 9999;
	
	CGSize size = [self sizeThatFits:maxSize];
	return size;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	
	if (self.needsScrollIfNeeded)
	{
		self.needsScrollIfNeeded = NO;
		
		if (self.contentSize.height > self.frame.size.height)
		{
			CGFloat y = self.contentSize.height - self.frame.size.height;
			[self setContentOffset:CGPointMake(0, y) animated:YES];
		}
		else
		{
			[self setContentOffset:CGPointMake(0, 0) animated:YES];
		}
	}
}

@end
