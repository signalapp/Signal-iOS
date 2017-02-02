//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAnyTouchGestureRecognizer.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@implementation OWSAnyTouchGestureRecognizer

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer
{
    return NO;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer
{
    return NO;
}

- (BOOL)shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return NO;
}

- (BOOL)shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];

    if (self.state == UIGestureRecognizerStatePossible && [self isValidTouch:touches event:event]) {
        self.state = UIGestureRecognizerStateRecognized;
    } else {
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (BOOL)isValidTouch:(NSSet<UITouch *> *)touches event:(UIEvent *)event
{
    if (event.allTouches.count > 1) {
        return NO;
    }
    if (touches.count != 1) {
        return NO;
    }

    UITouch *touch = touches.anyObject;
    CGPoint location = [touch locationInView:self.view];
    if (!CGRectContainsPoint(self.view.bounds, location)) {
        return NO;
    }

    if ([self subviewControlOfView:self.view containsTouch:touch]) {
        return NO;
    }

    return YES;
}

- (BOOL)subviewControlOfView:(UIView *)superview containsTouch:(UITouch *)touch
{
    for (UIView *subview in superview.subviews) {
        if (subview.hidden || !subview.userInteractionEnabled) {
            continue;
        }
        CGPoint location = [touch locationInView:subview];
        if (!CGRectContainsPoint(subview.bounds, location)) {
            continue;
        }
        if ([subview isKindOfClass:[UIControl class]]) {
            return YES;
        }
        if ([self subviewControlOfView:subview containsTouch:touch]) {
            return YES;
        }
    }

    return NO;
}

@end
