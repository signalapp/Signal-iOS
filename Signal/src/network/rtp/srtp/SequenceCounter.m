#import "SequenceCounter.h"

const int64_t ShortRange = ((int64_t)1) << 16;

@interface SequenceCounter ()

@property (nonatomic) uint16_t prevShortId;
@property (nonatomic) int64_t prevLongId;

@end

@implementation SequenceCounter

- (int64_t)convertNext:(uint16_t)nextShortId {
    int64_t delta = (int64_t)nextShortId - (int64_t)self.prevShortId;
    if (delta > INT16_MAX) delta -= ShortRange;
    if (delta < INT16_MIN) delta += ShortRange;
    int64_t nextLongId = self.prevLongId + delta;
    
    self.prevShortId = nextShortId;
    self.prevLongId = nextLongId;
    return nextLongId;
}

@end
