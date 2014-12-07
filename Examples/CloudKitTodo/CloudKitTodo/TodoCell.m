#import "TodoCell.h"


@implementation TodoCell

@synthesize delegate = _weak_delegate;

@synthesize checkmarkButton = checkmarkButton;
@synthesize titleLabel = titleLabel;

- (IBAction)didTapImageView:(id)sender
{
	id <NSObject> delegate = self.delegate;
	
	if ([delegate respondsToSelector:@selector(didTapImageViewInCell:)]) {
		[(id <TodoCellDelegate>)delegate didTapImageViewInCell:self];
	}
}

@end
