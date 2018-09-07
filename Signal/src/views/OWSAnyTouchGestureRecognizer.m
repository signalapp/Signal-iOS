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

- (UIView *)rootViewInViewHierarchy:(UIView *)view
{
    OWSAssertDebug(view);
    UIResponder *responder = view;
    UIView *lastView = nil;
    while (responder) {
        if ([responder isKindOfClass:[UIView class]]) {
            lastView = (UIView *)responder;
        }
        responder = [responder nextResponder];
    }
    return lastView;
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

    // Ignore touches that start near the top or bottom edge of the screen;
    // they may be a system edge swipe gesture.
    UIView *rootView = [self rootViewInViewHierarchy:self.view];
    CGPoint rootLocation = [touch locationInView:rootView];
    CGFloat distanceToTopEdge = MAX(0, rootLocation.y);
    CGFloat distanceToBottomEdge = MAX(0, rootView.bounds.size.height - rootLocation.y);
    CGFloat distanceToNearestEdge = MIN(distanceToTopEdge, distanceToBottomEdge);
    CGFloat kSystemEdgeSwipeTolerance = 50.f;
    if (distanceToNearestEdge < kSystemEdgeSwipeTolerance) {
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
