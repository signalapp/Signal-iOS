#import "DialerButtonView.h"
#import "UIUtil.h"

@implementation DialerButtonView

- (void)awakeFromNib {
    [super awakeFromNib];
    self.numberLabel.text = NSLocalizedString(self.numberLocalizationKey, @"");
    self.letterLabel.text = NSLocalizedString(self.letterLocalizationKey, @"");
    self.layer.cornerRadius = 4.0f;
    self.layer.borderColor = [UIUtil.darkBackgroundColor CGColor];
}

- (void)setSelected:(BOOL)isSelected {
    if (isSelected) {
        self.backgroundColor = UIUtil.transparentLightGrayColor;
        self.layer.borderWidth = 0.5f;
    } else {
        self.backgroundColor = UIColor.clearColor;
        self.layer.borderWidth = 0.0f;
    }
}

#pragma mark - Actions

- (void)buttonTouchUp {
    [self setSelected:NO];
    id delegate = self.delegate;
    [delegate dialerButtonViewDidSelect:self];
}

- (void)buttonTouchCancel {
    [self setSelected:NO];
}

- (void)buttonTouchDown {
    [self setSelected:YES];
}

@end
