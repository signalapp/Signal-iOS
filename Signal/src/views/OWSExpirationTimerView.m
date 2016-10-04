//  Created by Michael Kirk on 9/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSExpirationTimerView.h"
#import "MessagesViewController.h"
#import "UIColor+OWS.h"
#import <QuartzCore/CAShapeLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSExpirationTimerView ()

@property (nonatomic) uint32_t initialDurationSeconds;
@property (atomic) uint64_t expiresAtSeconds;

@property (nonatomic, readonly) UIImageView *emptyHourglassImageView;
@property (nonatomic, readonly) UIImageView *fullHourglassImageView;
@property CGFloat ratioRemaining;

@end

@implementation OWSExpirationTimerView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) {
        return self;
    }

    self.clipsToBounds = YES;

    _emptyHourglassImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_hourglass_empty"]];
    _emptyHourglassImageView.tintColor = [UIColor ows_blackColor];
    [self insertSubview:_emptyHourglassImageView atIndex:0];

    _fullHourglassImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_hourglass_full"]];
    _fullHourglassImageView.tintColor = [UIColor ows_darkGrayColor];
    [self insertSubview:_fullHourglassImageView atIndex:1];

    _ratioRemaining = 1.0f;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    self.clipsToBounds = YES;

    _emptyHourglassImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_hourglass_empty"]];
    _emptyHourglassImageView.tintColor = [UIColor lightGrayColor];
    [self insertSubview:_emptyHourglassImageView atIndex:1];

    _fullHourglassImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_hourglass_full"]];
    _fullHourglassImageView.tintColor = [UIColor lightGrayColor];
    [self insertSubview:_fullHourglassImageView atIndex:0];

    _ratioRemaining = 1.0f;

    return self;
}

- (void)layoutSubviews
{
    CGFloat leftMargin = 0.0f;
    CGFloat padding = 6.0f;
    CGRect hourglassFrame
        = CGRectMake(leftMargin, padding / 2, self.frame.size.height - padding, self.frame.size.height - padding);
    self.emptyHourglassImageView.frame = hourglassFrame;
    self.emptyHourglassImageView.bounds = hourglassFrame;
    self.fullHourglassImageView.frame = hourglassFrame;
    self.fullHourglassImageView.bounds = hourglassFrame;

}

- (void)restartAnimation:(NSNotification *)notification
{
    [self startTimerWithExpiresAtSeconds:self.expiresAtSeconds initialDurationSeconds:self.initialDurationSeconds];
}

- (void)startTimerWithExpiresAtSeconds:(uint64_t)expiresAtSeconds
                initialDurationSeconds:(uint32_t)initialDurationSeconds
{
    if (expiresAtSeconds == 0) {
        DDLogWarn(@"%@ Asked to animate expiration for message with expiresAtSeconds:0 intitialDurationSeconds:%u",
            self.logTag,
            initialDurationSeconds);
    }

    DDLogVerbose(@"%@ Starting animation timer with expiresAtSeconds: %llu initialDurationSeconds: %d",
        self.logTag,
        expiresAtSeconds,
        initialDurationSeconds);

    self.expiresAtSeconds = expiresAtSeconds;
    self.initialDurationSeconds = initialDurationSeconds;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(restartAnimation:)
                                                 name:OWSMessagesViewControllerDidAppearNotification
                                               object:nil];

    double secondsLeft = self.expiresAtSeconds - [NSDate new].timeIntervalSince1970;

    if (secondsLeft > INT_MAX) { // overflow
        secondsLeft = 0;
    }

    // Get hourglass frames to the proper size.
    [self setNeedsLayout];
    [self layoutIfNeeded];

    CAGradientLayer *maskLayer = [CAGradientLayer new];
    self.fullHourglassImageView.layer.mask = maskLayer;

    maskLayer.frame = self.fullHourglassImageView.frame;

    // Blur the top of the mask a bit with gradient
    maskLayer.colors = @[ (id)[UIColor clearColor].CGColor, (id)[UIColor blackColor].CGColor ];
    maskLayer.startPoint = CGPointMake(0.5f, 0);
    maskLayer.endPoint = CGPointMake(0.5f, 0.2f);

    CGFloat ratioRemaining = ((CGFloat)secondsLeft / (CGFloat)self.initialDurationSeconds);
    if (ratioRemaining < 0) {
        ratioRemaining = 0.0;
    }
    CGPoint defaultPosition = maskLayer.position;
    CGPoint finalPosition = CGPointMake(defaultPosition.x, defaultPosition.y + maskLayer.bounds.size.height);
    CGPoint startingPosition
        = CGPointMake(defaultPosition.x, finalPosition.y - maskLayer.bounds.size.height * ratioRemaining);
    maskLayer.position = startingPosition;

    CABasicAnimation *revealAnimation = [CABasicAnimation animationWithKeyPath:@"position"];
    revealAnimation.duration = secondsLeft;
    revealAnimation.fromValue = [NSValue valueWithCGPoint:startingPosition];
    revealAnimation.toValue = [NSValue valueWithCGPoint:finalPosition];

    [maskLayer addAnimation:revealAnimation forKey:@"revealAnimation"];
    maskLayer.position = finalPosition; // don't snap back

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ((long long)secondsLeft - 2) * (long long)NSEC_PER_SEC),
        dispatch_get_main_queue(),
        ^{
            [self startBlinking];
        });
}

- (void)startBlinking
{
    CABasicAnimation *blinkAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    blinkAnimation.duration = 0.5;
    blinkAnimation.fromValue = @(1.0);
    blinkAnimation.toValue = @(0.0);
    blinkAnimation.repeatCount = 4;
    blinkAnimation.autoreverses = YES;
    blinkAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:blinkAnimation forKey:@"alphaBlink"];
}

- (void)stopBlinking
{
    [self.layer removeAnimationForKey:@"alphaBlink"];
    self.layer.opacity = 1;
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
