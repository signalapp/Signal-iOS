#import <Foundation/Foundation.h>
#import "BufferDepthMeasure.h"
#import "DecayingSampleEstimator.h"
#import "DesiredBufferDepthController.h"

/**
 *
 * StretchFactorController determines when and how much to stretch audio.
 * When the amount of buffered audio is more than desired, audio is shrunk (sped up).
 * When the amount of buffered audio is less than desired, audio is expanded (slowed down).
 *
 **/

@interface StretchFactorController : NSObject

- (instancetype)initForJitterQueue:(JitterQueue*)jitterQueue;

- (double)getAndUpdateDesiredStretchFactor;

@end
