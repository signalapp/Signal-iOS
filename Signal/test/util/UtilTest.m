//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UtilTest.h"
#import "Util.h"
#import "TestUtil.h"

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
-(void) testToRegex {
    testThrows(@"(".toRegularExpression);
    NSRegularExpression* r = @"a+b".toRegularExpression;
    test([r numberOfMatchesInString:@"a" options:NSMatchingAnchored range:NSMakeRange(0, 1)] == 0);
    test([r numberOfMatchesInString:@"b" options:NSMatchingAnchored range:NSMakeRange(0, 1)] == 0);
    test([r numberOfMatchesInString:@"ba" options:NSMatchingAnchored range:NSMakeRange(0, 1)] == 0);
    test([r numberOfMatchesInString:@"ab" options:NSMatchingAnchored range:NSMakeRange(0, 2)] == 1);
    test([r numberOfMatchesInString:@"aab" options:NSMatchingAnchored range:NSMakeRange(0, 3)] == 1);
    test([r numberOfMatchesInString:@"aabXBNSAUI" options:NSMatchingAnchored range:NSMakeRange(0, 3)] == 1);
    test([r numberOfMatchesInString:@"aacb" options:NSMatchingAnchored range:NSMakeRange(0, 3)] == 0);
}
-(void) testWithMatchesAgainstReplacedBy {
    test([[@"(555)-555-5555" withMatchesAgainst:[@"[^0-9+]" toRegularExpression] replacedBy:@""] isEqualToString:@"5555555555"]);
    test([[@"aaaaaa" withMatchesAgainst:@"a".toRegularExpression replacedBy:@""] isEqualToString:@""]);
    test([[@"aabaabaa" withMatchesAgainst:@"b".toRegularExpression replacedBy:@"wonder"] isEqualToString:@"aawonderaawonderaa"]);
}
-(void) testContainsAnyMatches {
    NSRegularExpression* r = [@"^\\+[0-9]{10,}" toRegularExpression];
    test([@"+5555555555" containsAnyMatches:r]);
    test([@"+6555595555" containsAnyMatches:r]);
    test([@"+65555555557+/few,pf" containsAnyMatches:r]);
    test(![@" +5555555555" containsAnyMatches:r]);
    test(![@"+555KL55555" containsAnyMatches:r]);
    test(![@"+1-555-555-5555" containsAnyMatches:r]);
    test(![@"1-(555)-555-5555" containsAnyMatches:r]);
}
-(void) testWithPrefixRemovedElseNull {
    test([[@"test" withPrefixRemovedElseNull:@""] isEqualToString:@"test"]);
    test([[@"test" withPrefixRemovedElseNull:@"t"] isEqualToString:@"est"]);
    test([[@"test" withPrefixRemovedElseNull:@"te"] isEqualToString:@"st"]);
    test([[@"test" withPrefixRemovedElseNull:@"tes"] isEqualToString:@"t"]);
    test([[@"test" withPrefixRemovedElseNull:@"test"] isEqualToString:@""]);
    test([@"test" withPrefixRemovedElseNull:@"test2"] == nil);
    test([@"test" withPrefixRemovedElseNull:@"a"] == nil);
    testThrows([@"test" withPrefixRemovedElseNull:nil]);
}
-(void) testFromJson {
    test([[@"{}" decodedAsJsonIntoDictionary] isEqualToDictionary:@{}]);
    test([[@"{\"a\":\"b\"}" decodedAsJsonIntoDictionary] isEqualToDictionary:@{@"a":@"b"}]);
    test([[@"{\"c\":5}" decodedAsJsonIntoDictionary] isEqualToDictionary:@{@"c":@5}]);
    test([[@"{\"a\":5,\"b\":true}" decodedAsJsonIntoDictionary] isEqualToDictionary:(@{@"a":@5,@"b":@YES})]);
    
    testThrows([@"" decodedAsJsonIntoDictionary]);
    testThrows([@"}" decodedAsJsonIntoDictionary]);
    testThrows([@"{{}" decodedAsJsonIntoDictionary]);
}
-(void) testHasLongLongValue {
    test((@0).hasLongLongValue);
    test((@1).hasLongLongValue);
    test((@-11).hasLongLongValue);
    test(@LONG_LONG_MAX.hasLongLongValue);
    test(@LONG_LONG_MIN.hasLongLongValue);
    test(!@ULONG_LONG_MAX.hasLongLongValue);
    test(@(pow(2, 62)).hasLongLongValue);
    test(!@(pow(2, 63)).hasLongLongValue);
    test(!@(-pow(2, 64)).hasLongLongValue);
    test(!(@0.5).hasLongLongValue);
}
-(void) testTryParseAsUnsignedInteger {
    test([@"" tryParseAsUnsignedInteger] == nil);
    test([@"88ffhih" tryParseAsUnsignedInteger] == nil);
    test([@"0xA" tryParseAsUnsignedInteger] == nil);
    test([@"A" tryParseAsUnsignedInteger] == nil);
    test([@"-1" tryParseAsUnsignedInteger] == nil);
    test([@"-" tryParseAsUnsignedInteger] == nil);

    test([[@"0" tryParseAsUnsignedInteger] isEqual:@0]);
    test([[@"00" tryParseAsUnsignedInteger] isEqual:@0]);
    test([[@"1" tryParseAsUnsignedInteger] isEqual:@1]);
    test([[@"01" tryParseAsUnsignedInteger] isEqual:@1]);
    test([[@"25" tryParseAsUnsignedInteger] isEqual:@25]);
    test([[(@NSUIntegerMax).description tryParseAsUnsignedInteger] isEqual:@NSUIntegerMax]);
    if (NSUIntegerMax == 4294967295UL) {
        test([@"4294967296" tryParseAsUnsignedInteger] == nil);
    }
    if (NSUIntegerMax == 18446744073709551615ULL) {
        test([@"18446744073709551616" tryParseAsUnsignedInteger] == nil);
    }

    NSString* max = (@NSUIntegerMax).description;
    NSString* farTooLarge = [max stringByAppendingString:max];
    test([farTooLarge tryParseAsUnsignedInteger] == nil);
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
-(void) testWithCharactersInRangeReplacedBy {
    testThrows([@"" withCharactersInRange:NSMakeRange(0, 0) replacedBy:nil]);
    testThrows([@"" withCharactersInRange:NSMakeRange(0, 1) replacedBy:@""]);
    testThrows([@"" withCharactersInRange:NSMakeRange(1, 0) replacedBy:@""]);
    testThrows([@"" withCharactersInRange:NSMakeRange(1, 1) replacedBy:@""]);
    testThrows([@"abc" withCharactersInRange:NSMakeRange(4, 0) replacedBy:@""]);
    testThrows([@"abc" withCharactersInRange:NSMakeRange(3, 1) replacedBy:@""]);
    testThrows([@"abc" withCharactersInRange:NSMakeRange(4, NSUIntegerMax) replacedBy:@""]);
    
    test([[@"" withCharactersInRange:NSMakeRange(0, 0) replacedBy:@""] isEqual:@""]);
    test([[@"" withCharactersInRange:NSMakeRange(0, 0) replacedBy:@"abc"] isEqual:@"abc"]);
    test([[@"abc" withCharactersInRange:NSMakeRange(0, 0) replacedBy:@"123"] isEqual:@"123abc"]);
    test([[@"abc" withCharactersInRange:NSMakeRange(3, 0) replacedBy:@"123"] isEqual:@"abc123"]);
    test([[@"abc" withCharactersInRange:NSMakeRange(2, 0) replacedBy:@"123"] isEqual:@"ab123c"]);
    test([[@"abcdef" withCharactersInRange:NSMakeRange(1, 2) replacedBy:@"1234"] isEqual:@"a1234def"]);
}

@end
