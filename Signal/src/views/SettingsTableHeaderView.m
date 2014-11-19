#import "SettingsTableHeaderView.h"

#define STATE_TRANSITION_ANIMATION_DURATION 0.25

@implementation SettingsTableHeaderView

- (void)setColumnStateExpanded:(BOOL)isExpanded andIsAnimated:(BOOL)animated {
    [UIView animateWithDuration:animated ? STATE_TRANSITION_ANIMATION_DURATION : 0.0 animations:^{
        if (isExpanded) {
            self.columnStateImageView.transform = CGAffineTransformMakeRotation(0 * M_PI/180);
        } else {
            self.columnStateImageView.transform = CGAffineTransformMakeRotation( 270 * (float)M_PI/180);
        }
    }];
}

@end
