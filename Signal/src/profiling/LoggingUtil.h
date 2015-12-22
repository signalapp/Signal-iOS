#import <Foundation/Foundation.h>
#import "DecayingSampleEstimator.h"
#import "Logging.h"

@interface LoggingUtil : NSObject

+ (id<ValueLogger>)throttleValueLogger:(id<ValueLogger>)valueLogger
       discardingAfterEventForDuration:(NSTimeInterval)duration;
+ (id<OccurrenceLogger>)throttleOccurrenceLogger:(id<OccurrenceLogger>)occurrenceLogger
                 discardingAfterEventForDuration:(NSTimeInterval)duration;
+ (id<ValueLogger>)getAccumulatingValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender;
+ (id<ValueLogger>)getDifferenceValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender;
+ (id<ValueLogger>)getAveragingValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender;
+ (id<ValueLogger>)getValueEstimateLoggerTo:(id<Logging>)logging
                                      named:(id)valueIdentity
                                       from:(id)sender
                              withEstimator:(DecayingSampleEstimator *)estimator;
+ (id<ValueLogger>)getMagnitudeDecayingToZeroValueLoggerTo:(id<Logging>)logging
                                                     named:(id)valueIdentity
                                                      from:(id)sender
                                           withDecayFactor:(double)decayFactorPerSample;

@end
