#import <Foundation/Foundation.h>

/// A sample estimate based on an exponential weighting of observed samples, favoring the latest samples.
@interface DecayingSampleEstimator : NSObject

@property (nonatomic, getter=currentEstimate, setter=forceEstimateTo:) double estimate;
@property (nonatomic, readonly, getter=decayRatePerUnitSample) double decayPerUnitSample;

- (instancetype)initWithInitialEstimate:(double)initialEstimate
                  andDecayPerUnitSample:(double)decayPerUnitSample;

- (instancetype)initWithInitialEstimate:(double)initialEstimate
                         andDecayFactor:(double)decayFactor
                            perNSamples:(double)decayPeriod;

// Decays the current estimate towards the given sample value, assuming a unit weighting.
- (void)updateWithNextSample:(double)sampleValue;

// Decays the current estimate towards the given sample value, with a given weighting.
- (void)updateWithNextSample:(double)sampleValue
            withSampleWeight:(double)weight;

@end
