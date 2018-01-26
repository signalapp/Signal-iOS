//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UtilTest.h"
#import "NumberUtil.h"
#import "TestUtil.h"
#import <SignalMessaging/NSString+OWS.h>

@interface NSString (OWS_Test)

- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet;

@end

#pragma mark -

@implementation UtilTest

-(void) testFloorMultiple {
    test([NumberUtil largestIntegerThatIsAtMost:0 andIsAMultipleOf:20] == 0);
    test([NumberUtil largestIntegerThatIsAtMost:1 andIsAMultipleOf:20] == 0);
    test([NumberUtil largestIntegerThatIsAtMost:5 andIsAMultipleOf:20] == 0);
    test([NumberUtil largestIntegerThatIsAtMost:15 andIsAMultipleOf:20] == 0);
    test([NumberUtil largestIntegerThatIsAtMost:19 andIsAMultipleOf:20] == 0);
    test([NumberUtil largestIntegerThatIsAtMost:20 andIsAMultipleOf:20] == 20);
    test([NumberUtil largestIntegerThatIsAtMost:21 andIsAMultipleOf:20] == 20);
}

-(void) testCeilingMultiple {
    test([NumberUtil smallestIntegerThatIsAtLeast:0 andIsAMultipleOf:20] == 0);
    test([NumberUtil smallestIntegerThatIsAtLeast:1 andIsAMultipleOf:20] == 20);
    test([NumberUtil smallestIntegerThatIsAtLeast:5 andIsAMultipleOf:20] == 20);
    test([NumberUtil smallestIntegerThatIsAtLeast:15 andIsAMultipleOf:20] == 20);
    test([NumberUtil smallestIntegerThatIsAtLeast:19 andIsAMultipleOf:20] == 20);
    test([NumberUtil smallestIntegerThatIsAtLeast:20 andIsAMultipleOf:20] == 20);
    test([NumberUtil smallestIntegerThatIsAtLeast:21 andIsAMultipleOf:20] == 40);
}

-(void) testCongruentDifferenceMod2ToThe16 {
    test([NumberUtil congruentDifferenceMod2ToThe16From:1 to:0xFFFF] == -2);
    test([NumberUtil congruentDifferenceMod2ToThe16From:1 to:10] == 9);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0xFFFF to:1] == 2);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0 to:0x8000] == -0x8000);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0x8000 to:0] == -0x8000);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0 to:0] == 0);
}

-(void) testRemoveAllCharactersIn {
    testThrows([@"" removeAllCharactersIn:nil]);

    test([[@"" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"1" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"1"]);
    test([[@"a" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"A" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"123%^&"]);

    test([[@"" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    test([[@"1" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    test([[@"a" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"a"]);
    test([[@"A" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"A"]);
    test([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"abc%^&"]);
}

-(void) testDigitsOnly {
    test([@"".digitsOnly isEqual:@""]);
    test([@"1".digitsOnly isEqual:@"1"]);
    test([@"a".digitsOnly isEqual:@""]);
    test([@"(555) 235-7111".digitsOnly isEqual:@"5552357111"]);
}

@end
