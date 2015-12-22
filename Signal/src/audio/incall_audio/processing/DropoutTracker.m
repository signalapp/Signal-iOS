#import "DropoutTracker.h"
#import "Util.h"

#define maxActionableLatency 0.3
#define binsPerPacket 2.0
#define PRIOR_LATENESS_LENGTH 6
#define LATE_BINS_LENGTH 20
#define LATE_BIN_WINDOW_IN_SECONDS 30.0

@implementation DropoutTracker

+ (DropoutTracker *)dropoutTrackerWithAudioDurationPerPacket:(NSTimeInterval)audioDurationPerPacket {
    DropoutTracker *d = [DropoutTracker new];

    d->audioDurationPerPacket = audioDurationPerPacket;
    d->sequenceCounter        = [SequenceCounter sequenceCounter];
    d->priorLatenesses        = [Queue new];
    d->lateBins               = [NSMutableArray array];

    for (NSUInteger i = 0; i < PRIOR_LATENESS_LENGTH; i++) {
        [d->priorLatenesses enqueue:@0.0];
    }
    for (NSUInteger i = 0; i < LATE_BINS_LENGTH; i++) {
        [d->lateBins addObject:[EventWindow eventWindowWithWindowDuration:LATE_BIN_WINDOW_IN_SECONDS]];
    }

    return d;
}

- (NSTimeInterval)detectPeak {
    NSTimeInterval possiblePeakLatency = [[priorLatenesses peekAt:PRIOR_LATENESS_LENGTH / 2] doubleValue];

    for (NSUInteger i = 0; i < PRIOR_LATENESS_LENGTH - 1; i++) {
        if ([[priorLatenesses peekAt:i] doubleValue] > possiblePeakLatency) {
            return -1;
        }
    }

    return possiblePeakLatency;
}

- (void)observeSequenceNumber:(uint16_t)sequenceNumber {
    int64_t expandedSequenceNumber = [sequenceCounter convertNext:sequenceNumber];
    if (!startTimeInitialized) {
        startTime            = [TimeUtil time];
        startTimeInitialized = true;
    }

    NSTimeInterval expectedTime = startTime + drift + expandedSequenceNumber * audioDurationPerPacket;
    NSTimeInterval now          = [TimeUtil time];
    NSTimeInterval secLate      = now - expectedTime;
    [priorLatenesses enqueue:@(secLate)];
    [priorLatenesses dequeue];

    // update zero time
    // if a packet arrives early, immediately update the timebase
    // if it arrives late, conservatively update the timebase
    drift += MIN(secLate, secLate / 50);

    // Was the last packet a local peak?
    NSTimeInterval peakLatency = [self detectPeak];
    if (peakLatency > 0) {
        NSUInteger lateBin = (NSUInteger)[NumberUtil clamp:peakLatency / (audioDurationPerPacket / binsPerPacket)
                                                     toMin:0
                                                    andMax:LATE_BINS_LENGTH - 1];

        if (peakLatency <= maxActionableLatency) {
            [lateBins[lateBin] addEventAtTime:now];
        }
    }
}

/// How many packets would we have needed to buffer to stay below the desired dropout event count
- (double)getDepthForThreshold:(NSUInteger)maxEvents {
    NSUInteger eventCount = 0;
    NSTimeInterval now    = [TimeUtil time];
    for (NSUInteger depth = LATE_BINS_LENGTH; depth > 0; depth--) {
        eventCount += [lateBins[depth - 1] countAfterRemovingEventsBeforeWindowEndingAt:now];
        if (eventCount > maxEvents) {
            return (depth - 1) / binsPerPacket;
        }
    }
    return -1 / binsPerPacket;
}

@end
