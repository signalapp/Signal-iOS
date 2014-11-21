#import "DialerButtonView.h"
#import "UIUtil.h"

@implementation DialerButtonView

- (void)awakeFromNib {
    [super awakeFromNib];
    _numberLabel.text = NSLocalizedString(_numberLocalizationKey, @"");
    _letterLabel.text = NSLocalizedString(_letterLocalizationKey, @"");
    
    self.layer.cornerRadius = CGRectGetHeight(self.layer.frame)/2.0f;
    
    self.layer.borderColor = [[UIUtil darkBackgroundColor] CGColor];
}

- (void)setSelected:(BOOL)isSelected {
		
    if (isSelected) {

        UIColor *color = [UIColor blackColor];
        self.layer.shadowColor = [color CGColor];
        self.layer.shadowRadius = 15.0f;
        self.layer.shadowOpacity = 1.0f;
        self.layer.shadowOffset = CGSizeZero;
        self.layer.masksToBounds = NO;

        
    } else {
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 0.0f;
    }
}

#pragma mark - Actions

- (void)buttonTouchUp {
    [self setSelected:NO];
    [_delegate dialerButtonViewDidSelect:self];
}

- (void)buttonTouchCancel {
    [self setSelected:NO];
}

- (void)buttonTouchDown {
    [self setSelected:YES];
}

@end
