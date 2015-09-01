//
//  FLAnimatedImageView.h
//  Flipboard
//
//  Created by Raphael Schaad on 7/8/13.
//  Copyright (c) 2013-2015 Flipboard. All rights reserved.
//


#import "FLAnimatedImageView.h"
#import "FLAnimatedImage.h"
#import <QuartzCore/QuartzCore.h>


@interface FLAnimatedImageView ()

// Override of public `readonly` properties as private `readwrite`
@property (nonatomic, strong, readwrite) UIImage *currentFrame;
@property (nonatomic, assign, readwrite) NSUInteger currentFrameIndex;

@property (nonatomic, assign) NSUInteger loopCountdown;
@property (nonatomic, assign) NSTimeInterval accumulator;
@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, assign) BOOL shouldAnimate; // Before checking this value, call `-updateShouldAnimate` whenever the animated image, window or superview has changed.
@property (nonatomic, assign) BOOL needsDisplayWhenImageBecomesAvailable;

@end


@implementation FLAnimatedImageView

#pragma mark - Accessors
#pragma mark Public

- (void)setAnimatedImage:(FLAnimatedImage *)animatedImage
{
    if (![_animatedImage isEqual:animatedImage]) {
        if (animatedImage) {
            // Clear out the image.
            super.image = nil;
            // Ensure disabled highlighting; it's not supported (see `-setHighlighted:`).
            super.highlighted = NO;
            // UIImageView seems to bypass some accessors when calculating its intrinsic content size, so this ensures its intrinsic content size comes from the animated image.
            [self invalidateIntrinsicContentSize];
        } else {
            // Stop animating before the animated image gets cleared out.
            [self stopAnimating];
        }
        
        _animatedImage = animatedImage;
        
        self.currentFrame = animatedImage.posterImage;
        self.currentFrameIndex = 0;
        if (animatedImage.loopCount > 0) {
            self.loopCountdown = animatedImage.loopCount;
        } else {
            self.loopCountdown = NSUIntegerMax;
        }
        self.accumulator = 0.0;
        
        // Start animating after the new animated image has been set.
        [self updateShouldAnimate];
        if (self.shouldAnimate) {
            [self startAnimating];
        }
        
        [self.layer setNeedsDisplay];
    }
}


#pragma mark - Life Cycle

- (void)dealloc
{
    // Removes the display link from all run loop modes.
    [_displayLink invalidate];
}


#pragma mark - UIView Method Overrides
#pragma mark Observing View-Related Changes

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}


- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}


#pragma mark Auto Layout

- (CGSize)intrinsicContentSize
{
    // Default to let UIImageView handle the sizing of its image, and anything else it might consider.
    CGSize intrinsicContentSize = [super intrinsicContentSize];
    
    // If we have have an animated image, use its image size.
    // UIImageView's intrinsic content size seems to be the size of its image. The obvious approach, simply calling `-invalidateIntrinsicContentSize` when setting an animated image, results in UIImageView steadfastly returning `{UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric}` for its intrinsicContentSize.
    // (Perhaps UIImageView bypasses its `-image` getter in its implementation of `-intrinsicContentSize`, as `-image` is not called after calling `-invalidateIntrinsicContentSize`.)
    if (self.animatedImage) {
        intrinsicContentSize = self.image.size;
    }
    
    return intrinsicContentSize;
}


#pragma mark - UIImageView Method Overrides
#pragma mark Image Data

- (UIImage *)image
{
    UIImage *image = nil;
    if (self.animatedImage) {
        // Initially set to the poster image.
        image = self.currentFrame;
    } else {
        image = super.image;
    }
    return image;
}


- (void)setImage:(UIImage *)image
{
    if (image) {
        // Clear out the animated image and implicitly pause animation playback.
        self.animatedImage = nil;
    }
    
    super.image = image;
}


#pragma mark Animating Images

- (void)startAnimating
{
    if (self.animatedImage) {
        // Lazily create the display link.
        if (!self.displayLink) {
            // It is important to note the use of a weak proxy here to avoid a retain cycle. `-displayLinkWithTarget:selector:`
            // will retain its target until it is invalidated. We use a weak proxy so that the image view will get deallocated
            // independent of the display link's lifetime. Upon image view deallocation, we invalidate the display
            // link which will lead to the deallocation of both the display link and the weak proxy.
            FLWeakProxy *weakProxy = [FLWeakProxy weakProxyForObject:self];
            self.displayLink = [CADisplayLink displayLinkWithTarget:weakProxy selector:@selector(displayDidRefresh:)];
            
            NSString *mode = NSDefaultRunLoopMode;
            // Enable playback during scrolling by allowing timer events (i.e. animation) with `NSRunLoopCommonModes`.
            // But too keep scrolling smooth, only do this for hardware with more than one core and otherwise keep it at the default `NSDefaultRunLoopMode`.
            // The only devices with single-core chips (supporting iOS 6+) are iPhone 3GS/4 and iPod Touch 4th gen.
            // Key off `activeProcessorCount` (as opposed to `processorCount`) since the system could shut down cores in certain situations.
            if ([NSProcessInfo processInfo].activeProcessorCount > 1) {
                mode = NSRunLoopCommonModes;
            }
            [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:mode];
            
            // Note: The display link's `.frameInterval` value of 1 (default) means getting callbacks at the refresh rate of the display (~60Hz).
            // Setting it to 2 divides the frame rate by 2 and hence calls back at every other frame.
        }
        self.displayLink.paused = NO;
    } else {
        [super startAnimating];
    }
}


- (void)stopAnimating
{
    if (self.animatedImage) {
        self.displayLink.paused = YES;
    } else {
        [super stopAnimating];
    }
}


- (BOOL)isAnimating
{
    BOOL isAnimating = NO;
    if (self.animatedImage) {
        isAnimating = self.displayLink && !self.displayLink.isPaused;
    } else {
        isAnimating = [super isAnimating];
    }
    return isAnimating;
}


#pragma mark Highlighted Image Unsupport

- (void)setHighlighted:(BOOL)highlighted
{
    // Highlighted image is unsupported for animated images, but implementing it breaks the image view when embedded in a UICollectionViewCell.
    if (!self.animatedImage) {
        [super setHighlighted:highlighted];
    }
}


#pragma mark - Private Methods
#pragma mark Animation

// Don't repeatedly check our window & superview in `-displayDidRefresh:` for performance reasons.
// Just update our cached value whenever the animated image, window or superview is changed.
- (void)updateShouldAnimate
{
    self.shouldAnimate = self.animatedImage && self.window && self.superview;
}


- (void)displayDidRefresh:(CADisplayLink *)displayLink
{
    // If for some reason a wild call makes it through when we shouldn't be animating, bail.
    // Early return!
    if (!self.shouldAnimate) {
        FLLogWarn(@"Trying to animate image when we shouldn't: %@", self);
        return;
    }
    
    NSNumber *delayTimeNumber = [self.animatedImage.delayTimesForIndexes objectForKey:@(self.currentFrameIndex)];
    // If we don't have a frame delay (e.g. corrupt frame), don't update the view but skip the playhead to the next frame (in else-block).
    if (delayTimeNumber) {
        NSTimeInterval delayTime = [delayTimeNumber floatValue];
        // If we have a nil image (e.g. waiting for frame), don't update the view nor playhead.
        UIImage *image = [self.animatedImage imageLazilyCachedAtIndex:self.currentFrameIndex];
        if (image) {
            FLLogVerbose(@"Showing frame %lu for animated image: %@", (unsigned long)self.currentFrameIndex, self.animatedImage);
            self.currentFrame = image;
            if (self.needsDisplayWhenImageBecomesAvailable) {
                [self.layer setNeedsDisplay];
                self.needsDisplayWhenImageBecomesAvailable = NO;
            }
            
            self.accumulator += displayLink.duration;
            
            // While-loop first inspired by & good Karma to: https://github.com/ondalabs/OLImageView/blob/master/OLImageView.m
            while (self.accumulator >= delayTime) {
                self.accumulator -= delayTime;
                self.currentFrameIndex++;
                if (self.currentFrameIndex >= self.animatedImage.frameCount) {
                    // If we've looped the number of times that this animated image describes, stop looping.
                    self.loopCountdown--;
                    if (self.loopCountdown == 0) {
                        [self stopAnimating];
                        return;
                    }
                    self.currentFrameIndex = 0;
                }
                // Calling `-setNeedsDisplay` will just paint the current frame, not the new frame that we may have moved to.
                // Instead, set `needsDisplayWhenImageBecomesAvailable` to `YES` -- this will paint the new image once loaded.
                self.needsDisplayWhenImageBecomesAvailable = YES;
            }
        } else {
            FLLogDebug(@"Waiting for frame %lu for animated image: %@", (unsigned long)self.currentFrameIndex, self.animatedImage);
#if defined(DEBUG) && DEBUG
            if ([self.debug_delegate respondsToSelector:@selector(debug_animatedImageView:waitingForFrame:duration:)]) {
                [self.debug_delegate debug_animatedImageView:self waitingForFrame:self.currentFrameIndex duration:(NSTimeInterval)self.displayLink.duration];
            }
#endif
        }
    } else {
        self.currentFrameIndex++;
    }
}


#pragma mark - CALayerDelegate (Informal)
#pragma mark Providing the Layer's Content

- (void)displayLayer:(CALayer *)layer
{
    layer.contents = (__bridge id)self.image.CGImage;
}


@end
