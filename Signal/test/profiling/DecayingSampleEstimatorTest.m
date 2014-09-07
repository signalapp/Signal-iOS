#import <XCTest/XCTest.h>
#import "DecayingSampleEstimator.h"
#import "TestUtil.h"

@interface DecayingSampleEstimatorTest : XCTestCase

@end

@implementation DecayingSampleEstimatorTest
-(void) testDecayingSampleEstimator {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:1.0 andDecayPerUnitSample:0.5];
    test(e.currentEstimate == 1.0);
    test([e decayRatePerUnitSample] == 0.5);
    
    [e updateWithNextSample:2.0];
    test(e.currentEstimate == 1.5);
    test([e decayRatePerUnitSample] == 0.5);

    [e updateWithNextSample:2.0];
    test(e.currentEstimate == 1.75);
    test([e decayRatePerUnitSample] == 0.5);

    [e updateWithNextSample:1.75];
    test(e.currentEstimate == 1.75);

    [e updateWithNextSample:1.75];
    test(e.currentEstimate == 1.75);
}
-(void) testDecayingSampleEstimatorForce {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:1.0 andDecayPerUnitSample:0.5];
    test(e.currentEstimate == 1.0);
    [e forceEstimateTo:5];
    test(e.currentEstimate == 5);
    test([e decayRatePerUnitSample] == 0.5);
}
-(void) testDecayingSampleEstimatorQuarter {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:1.0 andDecayPerUnitSample:0.75];
    test(e.currentEstimate == 1.0);
    test([e decayRatePerUnitSample] == 0.75);
    [e updateWithNextSample:2.0];
    test(e.currentEstimate == 1.75);
}
-(void) testDecayingSampleEstimatorCustomDecayPeriod {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:0 andDecayFactor:0.75 perNSamples:2];
    test([e decayRatePerUnitSample] == 0.5);
    
    [e updateWithNextSample:4];
    [e updateWithNextSample:4];
    test(e.currentEstimate == 3);
}
-(void) testDecayingSampleEstimatorWeighted {
    DecayingSampleEstimator* e1 = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:0.0 andDecayPerUnitSample:0.25];
    DecayingSampleEstimator* e2 = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:0.0 andDecayPerUnitSample:0.25];

    [e1 updateWithNextSample:2.0 withSampleWeight:0.5];
    [e1 updateWithNextSample:2.0 withSampleWeight:0.5];
    [e2 updateWithNextSample:2.0];
    test(ABS(e1.currentEstimate - e2.currentEstimate) < 0.00001);

    [e1 updateWithNextSample:-1.0 withSampleWeight:2.0];
    [e2 updateWithNextSample:-1.0];
    [e2 updateWithNextSample:-1.0];
    test(ABS(e1.currentEstimate - e2.currentEstimate) < 0.00001);
}
-(void) testDecayingSampleEstimatorCornerCase0 {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:1.0 andDecayPerUnitSample:0];
    test([e decayRatePerUnitSample] == 0);
    test(e.currentEstimate == 1.0);
    
    [e updateWithNextSample:5.0];
    test(e.currentEstimate == 1.0);
    
    [e updateWithNextSample:535325.0];
    test(e.currentEstimate == 1.0);
    
    [e updateWithNextSample:-535325.0];
    test(e.currentEstimate == 1.0);

    [e updateWithNextSample:100.0 withSampleWeight:0];
    test(e.currentEstimate == 1.0);

    [e updateWithNextSample:200.0 withSampleWeight:100];
    test(e.currentEstimate == 1.0);

    [e updateWithNextSample:300.0 withSampleWeight:1];
    test(e.currentEstimate == 1.0);
}
-(void) testDecayingSampleEstimatorCornerCase1 {
    DecayingSampleEstimator* e = [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:1.0 andDecayPerUnitSample:1];
    test([e decayRatePerUnitSample] == 1);
    test(e.currentEstimate == 1.0);
    
    [e updateWithNextSample:5.0];
    test(e.currentEstimate == 5.0);
    
    [e updateWithNextSample:535325.0];
    test(e.currentEstimate == 535325.0);
    
    [e updateWithNextSample:-535325.0];
    test(e.currentEstimate == -535325.0);

    [e updateWithNextSample:100.0 withSampleWeight:0.0001];
    test(e.currentEstimate == 100.0);
    
    [e updateWithNextSample:200.0 withSampleWeight:100];
    test(e.currentEstimate == 200.0);
    
    [e updateWithNextSample:300.0 withSampleWeight:1];
    test(e.currentEstimate == 300.0);

    [e updateWithNextSample:400.0 withSampleWeight:0];
    test(e.currentEstimate == 300.0);
}
@end
