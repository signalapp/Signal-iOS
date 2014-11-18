#import <Foundation/Foundation.h>
#import "PriorityQueue.h"
#import "EncodedAudioPacket.h"
#import "Logging.h"
#import "JitterQueueNotificationReceiver.h"
#import "BufferDepthMeasure.h"

/**
 *
 * JitterQueue handles the details of organizing and consuming real-time data, which may fail to arrive on time or arrive out of order.
 *
**/

@interface JitterQueue : NSObject <BufferDepthMeasure>

- (instancetype)init;

- (void)registerWatcher:(id<JitterQueueNotificationReceiver>)watcher;

// Provides a framed audio packet to be placed in sequence.
// Returns true if the packet was successfully enqueued.
// Returns false if the packet has arrived too late, far too early, or is a duplicate.
- (bool)tryEnqueue:(EncodedAudioPacket*)packet;

// Returns the next framed audio packet in sequence, or nil if the next packet has not arrived in time.
- (EncodedAudioPacket*)tryDequeue;

// The number of framed audio packets (contiguous or not) in the queue.
- (NSUInteger)count;

@end
