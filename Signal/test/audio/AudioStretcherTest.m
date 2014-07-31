#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "AudioStretcher.h"

@interface AudioStretcherTest : XCTestCase

@end

@implementation AudioStretcherTest
-(void) testStretchAudioStretches {
    for (NSNumber* s in @[@0.5, @1.0, @1.5]) {
        NSUInteger inputSampleCount = 8000;
        double stretch = [s doubleValue];
        double freq = 300;
        
        AudioStretcher* a = [AudioStretcher audioStretcher];
        
        NSData* inputData = sineWave(freq, 8000, 8000);
        NSData* outputData = [a stretchAudioData:inputData stretchFactor:stretch];
        NSUInteger outputSampleCount = [outputData length]/sizeof(int16_t);
        if ([s doubleValue] == 1) {
            test([inputData isEqualToData:outputData]);
        }
        
        double ratio = outputSampleCount / (double)inputSampleCount / stretch;
        test(ratio > 0.95 && ratio < 1.05);
    }
}
@end
