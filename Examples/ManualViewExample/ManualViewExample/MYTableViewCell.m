#import "MYTableViewCell.h"


@implementation MYTableViewCell {
	
	uint64_t current;
}

@synthesize customHighlightView = customHighlightView;
@synthesize nameLabel = nameLabel;

- (void)flash
{
	customHighlightView.alpha = 1.0;
	customHighlightView.hidden = NO;
	
	uint64_t last = ++current;
	
	[UIView animateWithDuration:1.0 animations:^{
		
		customHighlightView.alpha = 0.0;
		
	} completion:^(BOOL finished) {
		
		if (current == last) {
			customHighlightView.hidden = YES;
		}
	}];
}

@end
