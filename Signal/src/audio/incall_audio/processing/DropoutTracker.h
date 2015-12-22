#import <Foundation/Foundation.h>
#import "EventWindow.h"
#import "Queue.h"
#import "SequenceCounter.h"

/**
 *
 * This is a direct implementation of Redphone's DropoutTracker for android:
 *
 * > When a network dropout occurs packet latency will increase quickly to a maximum latency before
 * > quickly returning to a normal value.  These dropouts create local peaks in latency that we can
 * > detect.
 *
 * > DropoutTracker registers when packets with given sequence numbers arrive and
 * > attempts to predict when additional packets should arrive based on this information.
 *
 * > The predicted arrival times allow the estimation of an arrival  lateness value for each packet
 * > The last several lateness values are tracked and local peaks in lateness are detected
 *
 * > Peak latencies above a the "threshold of actionability" (300msec) are discarded since we never
 * > want to buffer more than 300msec worth of audio packets.
 *
 * > We track how many peaks occurred in several latency ranges (expressed as a packet count) and
 * > provide the ability to answer the question:
 *
 * > If we wanted to have only N buffer underflows in the past M seconds, how many packets would need
 * > to be stored in the buffer?
 *
 * > @author Stuart O. Anderson
 *
 * Link to android implementation with comments:
 * https://github.com/WhisperSystems/RedPhone/blob/2a6e8cec64cc457d2eb02351d0f3adf769db7a84/src/org/thoughtcrime/redphone/audio/DropoutTracker.java
 *
 */

@interface DropoutTracker : NSObject {
   @private
    Queue *priorLatenesses;
   @private
    NSMutableArray *lateBins;
   @private
    SequenceCounter *sequenceCounter;
   @private
    NSTimeInterval audioDurationPerPacket;
   @private
    bool startTimeInitialized;
   @private
    NSTimeInterval startTime;
   @private
    NSTimeInterval drift;
}

+ (DropoutTracker *)dropoutTrackerWithAudioDurationPerPacket:(NSTimeInterval)audioDurationPerPacket;
- (void)observeSequenceNumber:(uint16_t)seqNum;
- (double)getDepthForThreshold:(NSUInteger)maxEvents;

@end
