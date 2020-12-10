//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageTimerView.h"
#import "ConversationViewController.h"
#import "OWSMath.h"
#import "UIView+OWS.h"
#import <QuartzCore/QuartzCore.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kDisappearingMessageIconSize = 12.f;

@interface OWSMessageTimerView ()

@property (nonatomic) uint32_t initialDurationSeconds;
@property (nonatomic) uint64_t expirationTimestamp;
@property (nonatomic) UIColor *tintColor;

@property (nonatomic) UIImageView *imageView;

@property (nonatomic, nullable) NSTimer *animationTimer;

// 0 == about to expire, 12 == just started countdown.
@property (nonatomic) NSInteger progress12;


@end

#pragma mark -

@implementation OWSMessageTimerView

- (void)dealloc
{
    [self clearAnimation];
}

- (instancetype)init
{
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    self.imageView = [UIImageView new];
    [self addSubview:self.imageView];
    [self.imageView autoPinEdgesToSuperviewEdges];
    [self.imageView autoSetDimension:ALDimensionWidth toSize:kDisappearingMessageIconSize];
    [self.imageView autoSetDimension:ALDimensionHeight toSize:kDisappearingMessageIconSize];
}

- (void)configureWithExpirationTimestamp:(uint64_t)expirationTimestamp
                  initialDurationSeconds:(uint32_t)initialDurationSeconds
                               tintColor:(UIColor *)tintColor
{
    self.expirationTimestamp = expirationTimestamp;
    self.initialDurationSeconds = initialDurationSeconds;
    self.tintColor = tintColor;

    [self updateProgress12];
    [self updateIcon];
    [self startAnimation];
}

- (void)updateProgress12
{
    BOOL hasStartedCountdown = self.expirationTimestamp > 0;
    if (!hasStartedCountdown) {
        self.progress12 = 12;
        return;
    }

    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    CGFloat secondsLeft
        = (self.expirationTimestamp > nowTimestamp ? (self.expirationTimestamp - nowTimestamp) / 1000.f : 0.f);
    CGFloat progress = 0.f;
    if (self.initialDurationSeconds > 0) {
        progress = CGFloatClamp(secondsLeft / self.initialDurationSeconds, 0.f, 1.f);
    }
    OWSAssertDebug(progress >= 0.f);
    OWSAssertDebug(progress <= 1.f);

    self.progress12 = (NSInteger)round(CGFloatClamp(progress, 0.f, 1.f) * 12);
}

- (void)setProgress12:(NSInteger)progress12
{
    if (_progress12 == progress12) {
        return;
    }
    _progress12 = progress12;

    [self updateIcon];
}

- (void)updateIcon
{
    self.imageView.image = [[self progressIcon] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.imageView.tintColor = self.tintColor;
}

- (UIImage *)progressIcon
{
    OWSAssertDebug(self.progress12 >= 0);
    OWSAssertDebug(self.progress12 <= 12);

    UIImage *_Nullable image = [UIImage imageNamed:[NSString stringWithFormat:@"timer-%02ld-12", self.progress12 * 5]];
    OWSAssertDebug(image);
    OWSAssertDebug(image.size.width == kDisappearingMessageIconSize);
    OWSAssertDebug(image.size.height == kDisappearingMessageIconSize);
    return image;
}

- (void)startAnimation
{
    OWSAssertIsOnMainThread();

    [self clearAnimation];

    self.animationTimer = [NSTimer weakTimerWithTimeInterval:0.1f
                                                      target:self
                                                    selector:@selector(updateProgress12)
                                                    userInfo:nil
                                                     repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
}

- (void)clearAnimation
{
    OWSAssertIsOnMainThread();

    [self.animationTimer invalidate];
    self.animationTimer = nil;
}

- (void)prepareForReuse
{
    [self clearAnimation];
}

+ (CGSize)measureSize
{
    return CGSizeMake(kDisappearingMessageIconSize, kDisappearingMessageIconSize);
}

@end

NS_ASSUME_NONNULL_END
