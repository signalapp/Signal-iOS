//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSExpirationTimerView.h"
#import "ConversationViewController.h"
#import "NSDate+OWS.h"
#import "OWSMath.h"
#import "UIColor+OWS.h"
#import "UIView+OWS.h"
#import <QuartzCore/QuartzCore.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kExpirationTimerViewSize = 16.f;

@interface OWSExpirationTimerView ()

@property (nonatomic) uint32_t initialDurationSeconds;
@property (nonatomic) uint64_t expirationTimestamp;

@property (nonatomic, readonly) UIImageView *emptyHourglassImageView;
@property (nonatomic, readonly) UIImageView *fullHourglassImageView;
@property (nonatomic, nullable) CAGradientLayer *maskLayer;
@property (nonatomic, nullable) NSTimer *animationTimer;

@end

#pragma mark -

@implementation OWSExpirationTimerView

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithExpiration:(uint64_t)expirationTimestamp initialDurationSeconds:(uint32_t)initialDurationSeconds
{
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return self;
    }

    self.expirationTimestamp = expirationTimestamp;
    self.initialDurationSeconds = initialDurationSeconds;

    [self commonInit];

    return self;
}

- (void)commonInit
{
    self.clipsToBounds = YES;
    
    UIImage *hourglassEmptyImage = [[UIImage imageNamed:@"ic_hourglass_empty"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *hourglassFullImage = [[UIImage imageNamed:@"ic_hourglass_full"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _emptyHourglassImageView = [[UIImageView alloc] initWithImage:hourglassEmptyImage];
    self.emptyHourglassImageView.tintColor = [UIColor lightGrayColor];
    [self addSubview:self.emptyHourglassImageView];
    
    _fullHourglassImageView = [[UIImageView alloc] initWithImage:hourglassFullImage];
    self.fullHourglassImageView.tintColor = [UIColor lightGrayColor];
    [self addSubview:self.fullHourglassImageView];

    [self.emptyHourglassImageView autoPinHeightToSuperviewWithMargin:2.f];
    [self.emptyHourglassImageView autoHCenterInSuperview];
    [self.emptyHourglassImageView autoPinToSquareAspectRatio];
    [self.fullHourglassImageView autoPinHeightToSuperviewWithMargin:2.f];
    [self.fullHourglassImageView autoHCenterInSuperview];
    [self.fullHourglassImageView autoPinToSquareAspectRatio];
    [self autoSetDimension:ALDimensionWidth toSize:kExpirationTimerViewSize];
    [self autoSetDimension:ALDimensionHeight toSize:kExpirationTimerViewSize];
}

- (void)clearAnimations
{
    [self.layer removeAllAnimations];
    [self.maskLayer removeAllAnimations];
    [self.maskLayer removeFromSuperlayer];
    self.maskLayer = nil;
    [self.fullHourglassImageView.layer.mask removeFromSuperlayer];
    self.fullHourglassImageView.layer.mask = nil;
    self.layer.opacity = 1.f;
    self.emptyHourglassImageView.hidden = YES;
    self.fullHourglassImageView.hidden = YES;
    [self.animationTimer invalidate];
    self.animationTimer = nil;
}

- (void)setFrame:(CGRect)frame {
    BOOL sizeDidChange = CGSizeEqualToSize(self.frame.size, frame.size);
    [super setFrame:frame];
    if (sizeDidChange) {
        [self ensureAnimations];
    }
}

- (void)setBounds:(CGRect)bounds {
    BOOL sizeDidChange = CGSizeEqualToSize(self.bounds.size, bounds.size);
    [super setBounds:bounds];
    if (sizeDidChange) {
        [self ensureAnimations];
    }
}

- (void)ensureAnimations
{
    OWSAssert([NSThread isMainThread]);
    
    CGFloat secondsLeft = MAX(0, (self.expirationTimestamp - [NSDate ows_millisecondTimeStamp]) / 1000.f);

    [self clearAnimations];
    
    const NSTimeInterval kBlinkAnimationDurationSeconds = 2;

    if (self.expirationTimestamp == 0) {
        // If message hasn't started expiring yet, just show the full hourglass.
        self.fullHourglassImageView.hidden = NO;
        return;
    } else if (secondsLeft <= kBlinkAnimationDurationSeconds + 0.1f) {
        // If message has expired, just show the blinking empty hourglass.
        self.emptyHourglassImageView.hidden = NO;
        
        // Flashing animation.
        [UIView animateWithDuration:0.5f
            delay:0.f
            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat
            animations:^{
                self.layer.opacity = 0.f;
            }
            completion:^(BOOL finished) {
                self.layer.opacity = 1.f;
            }];
        return;
    }

    self.emptyHourglassImageView.hidden = NO;
    self.fullHourglassImageView.hidden = NO;

    CAGradientLayer *maskLayer = [CAGradientLayer new];
    maskLayer.frame = self.fullHourglassImageView.bounds;
    self.maskLayer = maskLayer;
    self.fullHourglassImageView.layer.mask = maskLayer;
    
    // Blur the top of the mask a bit with gradient
    maskLayer.colors = @[ (id)[UIColor clearColor].CGColor, (id)[UIColor blackColor].CGColor ];
    maskLayer.startPoint = CGPointMake(0.5f, 0.f);
    // Use a mask that is 20% tall to soften the edge of the animation.
    const CGFloat kMaskEdgeFraction = 0.2f;
    maskLayer.endPoint = CGPointMake(0.5f, kMaskEdgeFraction);
    
    NSTimeInterval timeUntilFlashing = MAX(0, secondsLeft - kBlinkAnimationDurationSeconds);
    
    CGFloat ratioRemaining = MAX(0.f, (timeUntilFlashing / (CGFloat)self.initialDurationSeconds));
    CGFloat alpha = 1.f - ratioRemaining;
    CGFloat maskRange = self.fullHourglassImageView.height;
    CGPoint startPosition = maskLayer.position;
    startPosition.y += CGFloatLerp(maskRange * -kMaskEdgeFraction, maskRange, alpha);
    CGPoint endPosition = maskLayer.position;
    endPosition.y += maskRange;

    maskLayer.position = startPosition;
    [CATransaction begin];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    animation.duration = timeUntilFlashing;
    animation.fromValue = [NSValue valueWithCGPoint:startPosition];
    animation.toValue = [NSValue valueWithCGPoint:endPosition];
    [maskLayer addAnimation:animation forKey:@"slideAnimation"];
    maskLayer.position = endPosition; // don't snap back
    [CATransaction commit];
    
    self.animationTimer = [NSTimer weakScheduledTimerWithTimeInterval:timeUntilFlashing
                                                               target:self
                                                             selector:@selector(ensureAnimations)
                                                             userInfo:nil
                                                              repeats:NO];
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
