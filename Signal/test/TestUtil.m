#import "TestUtil.h"

NSObject* churnLock(void) {
    static NSObject* shared = nil;
    if (shared == nil) {
        shared = [NSObject new];
    }
    return shared;
}
bool _testChurnHelper(int (^condition)(), NSTimeInterval delay) {
    NSTimeInterval t = [TimeUtil time] + delay;
    while ([TimeUtil time] < t) {
        @synchronized(churnLock()) {
            if (condition()) return true;
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    @synchronized(churnLock()) {
        return condition();
    }
}
NSData* increasingData(NSUInteger n) {
    return increasingDataFrom(0, n);
}
NSData* increasingDataFrom(NSUInteger offset, NSUInteger n) {
    uint8_t v[n];
    for (NSUInteger i = 0; i < n; i++)
        v[i] = (uint8_t)((i+offset) & 0xFF);
    return [NSData dataWithBytes:v length:n];
}
NSData* sineWave(double frequency, double sampleRate, NSUInteger sampleCount) {
    double tau = 6.283;
    
    int16_t samples[sampleCount];
    for (NSUInteger i = 0; i < sampleCount; i++) {
        samples[i] = (int16_t)(sin(frequency/sampleRate*i*tau)*(1<<15));
    }
    
    return [NSData dataWithBytes:samples length:sizeof(samples)];
}
NSData* generatePseudoRandomData(NSUInteger length) {
    NSMutableData* r = [NSMutableData dataWithLength:length];
    for (int i = 0; i < 16; i++) {
        ((uint8_t*)[r mutableBytes])[i] = (uint8_t)arc4random_uniform(256);
    }
    return r;
}
