#import "DropoutTracker.h"
#import "Util.h"
#import "Constraints.h"
#import "Environment.h"
#import "TimeUtil.h"

#define maxActionableLatency 0.3
#define binsPerPacket 2.0
#define PRIOR_LATENESS_LENGTH 6
#define LATE_BINS_LENGTH 20
#define LATE_BIN_WINDOW_IN_SECONDS 30.0

@interface DropoutTracker ()

@property (strong, nonatomic) Queue* priorLatenesses;
@property (strong, nonatomic) NSMutableArray* lateBins;
@property (strong, nonatomic) SequenceCounter* sequenceCounter;
@property (nonatomic) NSTimeInterval audioDurationPerPacket;
@property (nonatomic) bool startTimeInitialized;
@property (nonatomic) NSTimeInterval startTime;
@property (nonatomic) NSTimeInterval drift;

@end

@implementation DropoutTracker

- (instancetype)initWithAudioDurationPerPacket:(NSTimeInterval)audioDurationPerPacket {
    if (self = [super init]) {
        self.audioDurationPerPacket = audioDurationPerPacket;
        self.sequenceCounter = [[SequenceCounter alloc] init];
        self.priorLatenesses = [[Queue alloc] init];
        self.lateBins = [[NSMutableArray alloc] init];
        
        for (NSUInteger i = 0; i < PRIOR_LATENESS_LENGTH; i++) {
            [self.priorLatenesses enqueue:@0.0];
        }
        
        for (NSUInteger i = 0; i < LATE_BINS_LENGTH; i++) {
            [self.lateBins addObject:[[EventWindow alloc] initWithWindowDuration:LATE_BIN_WINDOW_IN_SECONDS]];
        }
    }
    
    return self;
}

- (NSTimeInterval)detectPeak {
    NSTimeInterval possiblePeakLatency = [[self.priorLatenesses peekAt:PRIOR_LATENESS_LENGTH/2] doubleValue];
    
    for (NSUInteger i=0; i < PRIOR_LATENESS_LENGTH-1; i++) {
        if ([[self.priorLatenesses peekAt:i] doubleValue] > possiblePeakLatency) {
            return -1;
        }
    }
    
    return possiblePeakLatency;
}

- (void)observeSequenceNumber:(uint16_t)sequenceNumber {
    int64_t expandedSequenceNumber = [self.sequenceCounter convertNext:sequenceNumber];
    if (!self.startTimeInitialized) {
        self.startTime = [TimeUtil time];
        self.startTimeInitialized = true;
    }
    
    NSTimeInterval expectedTime = self.startTime + self.drift + expandedSequenceNumber * self.audioDurationPerPacket;
    NSTimeInterval now = [TimeUtil time];
    NSTimeInterval secLate = now - expectedTime;
    [self.priorLatenesses enqueue:@(secLate)];
    [self.priorLatenesses dequeue];
    
    // update zero time
    // if a packet arrives early, immediately update the timebase
    // if it arrives late, conservatively update the timebase
    self.drift += MIN(secLate, secLate / 50);

    //Was the last packet a local peak?
    NSTimeInterval peakLatency = [self detectPeak];
    if (peakLatency > 0) {
        NSUInteger lateBin = (NSUInteger)[NumberUtil clamp:peakLatency / (self.audioDurationPerPacket / binsPerPacket)
                                                     toMin:0
                                                    andMax:LATE_BINS_LENGTH - 1];
        
        if (peakLatency <= maxActionableLatency) {
            [self.lateBins[lateBin] addEventAtTime:now];
        }
    }
    
}

/// How many packets would we have needed to buffer to stay below the desired dropout event count
- (double)getDepthForThreshold:(NSUInteger)maxEvents {
    NSUInteger eventCount = 0;
    NSTimeInterval now = [TimeUtil time];
    for (NSUInteger depth = LATE_BINS_LENGTH; depth > 0; depth--) {
        eventCount += [self.lateBins[depth-1] countAfterRemovingEventsBeforeWindowEndingAt:now];
        if (eventCount > maxEvents) {
            return (depth - 1) / binsPerPacket;
        }
    }
    return -1 / binsPerPacket;
}

@end
