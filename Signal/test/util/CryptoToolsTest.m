//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "Util.h"
#import "CryptoTools.h"
#import "TestUtil.h"

@interface CryptoToolsTest : XCTestCase

@end

@implementation CryptoToolsTest

-(void) testRandomForVariance {
    NSData* d = [CryptoTools generateSecureRandomData:8];
    NSData* d2 = [CryptoTools generateSecureRandomData:8];
    
    test(5 == [[CryptoTools generateSecureRandomData:5] length]);
    test(8 == d.length);
    
    // extremely unlikely to fail if any reasonable amount of entropy is going into d and d2
    test(![d isEqualToData:d2]);
}

@end
