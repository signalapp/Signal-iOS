//
//  FLAnimatedImageView.h
//  Flipboard
//
//  Created by Raphael Schaad on 7/8/13.
//  Copyright (c) 2013-2015 Flipboard. All rights reserved.
//


#import <UIKit/UIKit.h>

@class FLAnimatedImage;
@protocol FLAnimatedImageViewDebugDelegate;


//
//  An `FLAnimatedImageView` can take an `FLAnimatedImage` and plays it automatically when in view hierarchy and stops when removed.
//  The animation can also be controlled with the `UIImageView` methods `-start/stop/isAnimating`.
//  It is a fully compatible `UIImageView` subclass and can be used as a drop-in component to work with existing code paths expecting to display a `UIImage`.
//  Under the hood it uses a `CADisplayLink` for playback, which can be inspected with `currentFrame` & `currentFrameIndex`.
//
@interface FLAnimatedImageView : UIImageView

// Setting `[UIImageView.image]` to a non-`nil` value clears out existing `animatedImage`.
// And vice versa, setting `animatedImage` will initially populate the `[UIImageView.image]` to its `posterImage` and then start animating and hold `currentFrame`.
@property (nonatomic, strong) FLAnimatedImage *animatedImage;

@property (nonatomic, strong, readonly) UIImage *currentFrame;
@property (nonatomic, assign, readonly) NSUInteger currentFrameIndex;

#if defined(DEBUG) && DEBUG
// Only intended to report internal state for debugging
@property (nonatomic, weak) id<FLAnimatedImageViewDebugDelegate> debug_delegate;
#endif

@end


#if defined(DEBUG) && DEBUG
@protocol FLAnimatedImageViewDebugDelegate <NSObject>

@optional

- (void)debug_animatedImageView:(FLAnimatedImageView *)animatedImageView waitingForFrame:(NSUInteger)index duration:(NSTimeInterval)duration;

@end
#endif
