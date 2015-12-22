#import <Foundation/Foundation.h>
#import "DecayingSampleEstimator.h"
#import "DropoutTracker.h"
#import "Environment.h"
#import "JitterQueue.h"
#import "SpeexCodec.h"
#import "Terminable.h"

/**
 *
 * DesiredBufferDepthController is used to determine how much audio should be kept in reserve, in case of network
 *jitter.
 *
 * An instance must be registered to receive notifications from the network jitter queue in order to function correctly.
 * When packets arrive at a consistent rate without dropping, the desired buffer depth tends to decrease.
 * When packet delays vary significantly and when packets drop before arriving, the desired buffer tends to increase.
 *
 **/

@interface DesiredBufferDepthController : NSObject <Terminable, JitterQueueNotificationReceiver> {
   @private
    DropoutTracker *dropoutTracker;
   @private
    DecayingSampleEstimator *decayingDesiredBufferDepth;
   @private
    id<ValueLogger> desiredDelayLogger;
}

+ (DesiredBufferDepthController *)desiredBufferDepthControllerForJitterQueue:(JitterQueue *)jitterQueue;
- (double)getAndUpdateDesiredBufferDepth;

@end
