#import "AnonymousOccurrenceLogger.h"
#import "AnonymousValueLogger.h"
#import "Constraints.h"
#import "LoggingUtil.h"
#import "TimeUtil.h"

@implementation LoggingUtil

+ (id<ValueLogger>)throttleValueLogger:(id<ValueLogger>)valueLogger
       discardingAfterEventForDuration:(NSTimeInterval)duration {
    __block NSTimeInterval t = [TimeUtil time] - duration;
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      double t2 = [TimeUtil time];
      if (t2 - duration < t)
          return;
      t = t2;

      [valueLogger logValue:value];
    }];
}
+ (id<OccurrenceLogger>)throttleOccurrenceLogger:(id<OccurrenceLogger>)occurrenceLogger
                 discardingAfterEventForDuration:(NSTimeInterval)duration {
    __block NSTimeInterval t = [TimeUtil time] - duration;
    return [AnonymousOccurrenceLogger anonymousOccurencyLoggerWithMarker:^(id details) {
      double t2 = [TimeUtil time];
      if (t2 - duration < t)
          return;
      t = t2;

      [occurrenceLogger markOccurrence:details];
    }];
}

+ (id<ValueLogger>)getAccumulatingValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender {
    __block double total = 0.0;
    id<ValueLogger> norm = [logging getValueLoggerForValue:valueIdentity from:sender];
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      total += value;
      [norm logValue:total];
    }];
}
+ (id<ValueLogger>)getDifferenceValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender {
    __block double previous  = 0.0;
    __block bool hasPrevious = false;
    id<ValueLogger> norm     = [logging getValueLoggerForValue:valueIdentity from:sender];
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      double d = value - previous;
      previous = value;
      if (hasPrevious) {
          [norm logValue:d];
      }
      hasPrevious = true;
    }];
}
+ (id<ValueLogger>)getAveragingValueLoggerTo:(id<Logging>)logging named:(id)valueIdentity from:(id)sender {
    __block double total     = 0.0;
    __block NSUInteger count = 0;
    id<ValueLogger> norm     = [logging getValueLoggerForValue:valueIdentity from:sender];
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      total += value;
      count += 1;
      [norm logValue:total / count];
    }];
}
+ (id<ValueLogger>)getValueEstimateLoggerTo:(id<Logging>)logging
                                      named:(id)valueIdentity
                                       from:(id)sender
                              withEstimator:(DecayingSampleEstimator *)estimator {
    ows_require(estimator != nil);
    id<ValueLogger> norm = [logging getValueLoggerForValue:valueIdentity from:sender];
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      [estimator updateWithNextSample:value];
      [norm logValue:estimator.currentEstimate];
    }];
}
+ (id<ValueLogger>)getMagnitudeDecayingToZeroValueLoggerTo:(id<Logging>)logging
                                                     named:(id)valueIdentity
                                                      from:(id)sender
                                           withDecayFactor:(double)decayFactorPerSample {
    ows_require(decayFactorPerSample <= 1);
    ows_require(decayFactorPerSample >= 0);
    __block double decayingEstimate = 0.0;
    id<ValueLogger> norm            = [logging getValueLoggerForValue:valueIdentity from:sender];
    return [AnonymousValueLogger anonymousValueLogger:^(double value) {
      value            = ABS(value);
      decayingEstimate = MAX(value, decayingEstimate * decayFactorPerSample);
      [norm logValue:decayingEstimate];
    }];
}

@end
