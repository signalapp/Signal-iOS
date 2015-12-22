#import <Foundation/Foundation.h>
#import "BufferDepthMeasure.h"
#import "EncodedAudioPacket.h"
#import "JitterQueueNotificationReceiver.h"
#import "Logging.h"
#import "PriorityQueue.h"

/**
 *
 * JitterQueue handles the details of organizing and consuming real-time data, which may fail to arrive on time or
 *arrive out of order.
 *
**/

@interface JitterQueue : NSObject <BufferDepthMeasure> {
   @private
    PriorityQueue *resultPriorityQueue;
   @private
    uint16_t readHeadMin;
   @private
    uint16_t readHeadSpan;
   @private
    NSMutableSet *idsInJitterQueue;
   @private
    NSMutableArray *watchers;
   @private
    uint16_t largestLatestEnqueued;
}

+ (JitterQueue *)jitterQueue;

- (void)registerWatcher:(id<JitterQueueNotificationReceiver>)watcher;

// Provides a framed audio packet to be placed in sequence.
// Returns true if the packet was successfully enqueued.
// Returns false if the packet has arrived too late, far too early, or is a duplicate.
- (bool)tryEnqueue:(EncodedAudioPacket *)packet;

// Returns the next framed audio packet in sequence, or nil if the next packet has not arrived in time.
- (EncodedAudioPacket *)tryDequeue;

// The number of framed audio packets (contiguous or not) in the queue.
- (NSUInteger)count;

@end
