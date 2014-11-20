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

-(void) testArrayToUint8Data {
    test([[(@[]) ows_toUint8Data] length] == 0);

    NSData* d = [@[@0, @1] ows_toUint8Data];
    test(d.length == 2);
    test(((uint8_t*)[d bytes])[0] == 0);
    test(((uint8_t*)[d bytes])[1] == 1);
}
-(void) testArrayConcatDatas {
    NSData* d1 = [@[@0, @1] ows_toUint8Data];
    NSData* d2 = [@[@3, @4] ows_toUint8Data];
    NSData* d3 = [@[@6, @7] ows_toUint8Data];
    test([[@[] ows_concatDatas] isEqualToData:[(@[]) ows_toUint8Data]]);
    test([[@[d1] ows_concatDatas] isEqualToData:d1]);
    test([[(@[d1, d2, d3]) ows_concatDatas] isEqualToData:[(@[@0, @1, @3, @4, @6, @7]) ows_toUint8Data]]);
}

-(void) testDatadDecodedAsUtf8 {
    testThrows([[(@[@0xC3, @0x28]) ows_toUint8Data] decodedAsUtf8]);
    
    NSString* ab = [[(@[@97, @98]) ows_toUint8Data] decodedAsUtf8];
    NSString* ab0 = [[(@[@97, @98, @0]) ows_toUint8Data] decodedAsUtf8];
    test([ab isEqualToString:@"ab"]);
    test([ab0 isEqualToString:@"ab\0"]);
    test(![ab0  isEqualToString:ab]);
}
-(void) testTryFindFirstIndexOf {
    NSData* d = [@[@0, @1, @2, @3, @4, @5] ows_toUint8Data];
    NSData* d34 = [@[@3, @4] ows_toUint8Data];
    NSData* d67 = [@[@6, @7] ows_toUint8Data];
    NSData* d01 = [@[@0, @1] ows_toUint8Data];
    NSData* d02 = [@[@0, @2] ows_toUint8Data];
    
    test([[d tryFindIndexOf:[NSData data]] intValue] == 0);
    test([d tryFindIndexOf:d].intValue == 0);
    
    test([d tryFindIndexOf:d01].intValue == 0);
    test([d tryFindIndexOf:d02] == nil);
    test([d tryFindIndexOf:d34].intValue == 3);
    test([d34 tryFindIndexOf:d] == nil);
    test([d tryFindIndexOf:d67] == nil);
}
-(void) testDatadDecodedAsAscii {
    testThrows([[(@[@97, @0xAA]) ows_toUint8Data] decodedAsAscii]);

    NSString* ab = [[(@[@97, @98]) ows_toUint8Data] decodedAsAscii];
    NSString* ab0 = [[(@[@97, @98, @0]) ows_toUint8Data] decodedAsAscii];
    test([ab isEqualToString:@"ab"]);
    test([ab0 isEqualToString:@"ab\0"]);
    test(![ab0  isEqualToString:ab]);
}
-(void) testDatadDecodedAsAsciiReplacingErrorsWithDots {
    test([[[(@[@97, @98]) ows_toUint8Data] decodedAsAsciiReplacingErrorsWithDots] isEqualToString:@"ab"]);
    test([[[(@[@97, @98, @0, @127, @250]) ows_toUint8Data] decodedAsAsciiReplacingErrorsWithDots] isEqualToString:@"ab..."]);
}
-(void) testDataSkip {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d skip:0] isEqualToData:d]);
    test([[d skip:1] isEqualToData:[(@[@1, @2, @3]) ows_toUint8Data]]);
    test([[d skip:3] isEqualToData:[@[@3] ows_toUint8Data]]);
    test([[d skip:4] length] == 0);
    testThrows([d skip:5]);

    // stable
    NSMutableData* m = [NSMutableData dataWithLength:2];
    NSData* b = [m skip:1];
    NSData* b2 = [m skip:0];
    [m setUint8At:0 to:1];
    [m setUint8At:1 to:1];
    test([b uint8At:0] == 0);
    test([b2 uint8At:0] == 0);
}
-(void) testDataTake {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d take:0] length] == 0);
    test([[d take:1] isEqualToData:[(@[@0]) ows_toUint8Data]]);
    test([[d take:3] isEqualToData:[(@[@0, @1, @2]) ows_toUint8Data]]);
    test([[d take:4] isEqualToData:d]);
    testThrows([d take:5]);
    
    // stable
    NSMutableData* m = [NSMutableData dataWithLength:2];
    NSData* b = [m take:1];
    NSData* b2 = [m take:2];
    [m setUint8At:0 to:1];
    [m setUint8At:1 to:1];
    test([b uint8At:0] == 0);
    test([b2 uint8At:0] == 0);
}
-(void) testDataSkipLast {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d skipLast:0] isEqualToData:d]);
    test([[d skipLast:1] isEqualToData:[(@[@0, @1, @2]) ows_toUint8Data]]);
    test([[d skipLast:3] isEqualToData:[@[@0] ows_toUint8Data]]);
    test([[d skipLast:4] length] == 0);
    testThrows([d skipLast:5]);

    // stable
    NSMutableData* m = [NSMutableData dataWithLength:2];
    NSData* b = [m skipLast:1];
    NSData* b2 = [m skipLast:0];
    [m setUint8At:0 to:1];
    [m setUint8At:1 to:1];
    test([b uint8At:0] == 0);
    test([b2 uint8At:0] == 0);
}
-(void) testDataTakeLast {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d takeLast:0] length] == 0);
    test([[d takeLast:1] isEqualToData:[(@[@3]) ows_toUint8Data]]);
    test([[d takeLast:3] isEqualToData:[(@[@1, @2, @3]) ows_toUint8Data]]);
    test([[d takeLast:4] isEqualToData:d]);
    testThrows([d takeLast:5]);

    // stable
    NSMutableData* m = [NSMutableData dataWithLength:2];
    NSData* b = [m takeLast:1];
    NSData* b2 = [m takeLast:2];
    [m setUint8At:0 to:1];
    [m setUint8At:1 to:1];
    test([b uint8At:0] == 0);
    test([b2 uint8At:0] == 0);
}

-(void) testCongruentDifferenceMod2ToThe16 {
    test([NumberUtil congruentDifferenceMod2ToThe16From:1 to:0xFFFF] == -2);
    test([NumberUtil congruentDifferenceMod2ToThe16From:1 to:10] == 9);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0xFFFF to:1] == 2);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0 to:0x8000] == -0x8000);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0x8000 to:0] == -0x8000);
    test([NumberUtil congruentDifferenceMod2ToThe16From:0 to:0] == 0);
}
-(void) testSubdataVolatileAgainstReference {
    NSData* d = increasingData(10);
    for (NSUInteger i = 0; i < 10; i++) {
        for (NSUInteger j = 0; j < 10-i; j++) {
            NSData* s1 = [d subdataVolatileWithRange:NSMakeRange(i, j)];
            NSData* s2 = [d subdataWithRange:NSMakeRange(i, j)];
            test([s1 isEqualToData:s2]);
        }
    }
}
-(void) testSubdataVolatileErrorCases {
    NSData* d = increasingData(10);

    [d subdataVolatileWithRange:NSMakeRange(0, 0)];
    [d subdataVolatileWithRange:NSMakeRange(0, 10)];
    [d subdataVolatileWithRange:NSMakeRange(10, 0)];
    testThrows([d subdataVolatileWithRange:NSMakeRange(0, 11)]);
    testThrows([d subdataVolatileWithRange:NSMakeRange(11, 0)]);
    testThrows([d subdataVolatileWithRange:NSMakeRange(1, 10)]);
    testThrows([d subdataVolatileWithRange:NSMakeRange(10, 1)]);
    
    // potential wraparound cases
    testThrows([d subdataVolatileWithRange:NSMakeRange(NSUIntegerMax, 1)]);
    testThrows([d subdataVolatileWithRange:NSMakeRange(1, NSUIntegerMax)]);
}
-(void) testDataSkipVolatile {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d skipVolatile:0] isEqualToData:d]);
    test([[d skipVolatile:1] isEqualToData:[(@[@1, @2, @3]) ows_toUint8Data]]);
    test([[d skipVolatile:3] isEqualToData:[@[@3] ows_toUint8Data]]);
    test([[d skipVolatile:4] length] == 0);
    testThrows([d skipVolatile:5]);
}
-(void) testDataTakeVolatile {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d takeVolatile:0] length] == 0);
    test([[d takeVolatile:1] isEqualToData:[(@[@0]) ows_toUint8Data]]);
    test([[d takeVolatile:3] isEqualToData:[(@[@0, @1, @2]) ows_toUint8Data]]);
    test([[d takeVolatile:4] isEqualToData:d]);
    testThrows([d takeVolatile:5]);
}
-(void) testDataSkipLastVolatile {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d skipLastVolatile:0] isEqualToData:d]);
    test([[d skipLastVolatile:1] isEqualToData:[(@[@0, @1, @2]) ows_toUint8Data]]);
    test([[d skipLastVolatile:3] isEqualToData:[@[@0] ows_toUint8Data]]);
    test([[d skipLastVolatile:4] length] == 0);
    testThrows([d skipLastVolatile:5]);
}
-(void) testDataTakeLastVolatile {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([[d takeLastVolatile:0] length] == 0);
    test([[d takeLastVolatile:1] isEqualToData:[(@[@3]) ows_toUint8Data]]);
    test([[d takeLastVolatile:3] isEqualToData:[(@[@1, @2, @3]) ows_toUint8Data]]);
    test([[d takeLastVolatile:4] isEqualToData:d]);
    testThrows([d takeLastVolatile:5]);
}

-(void) testDataUint8At {
    NSData* d = [@[@0, @1, @2, @3] ows_toUint8Data];
    test([d uint8At:0] == 0);
    test([d uint8At:1] == 1);
    test([d uint8At:2] == 2);
    test([d uint8At:3] == 3);
    testThrows([d uint8At:4]);
}
-(void) testDataSetUint8At {
    NSMutableData* d = [NSMutableData dataWithLength:4];
    [d setUint8At:0 to:11];
    [d setUint8At:1 to:12];
    [d setUint8At:2 to:13];
    [d setUint8At:3 to:14];
    testThrows([d setUint8At:4 to:15]);
    test([d isEqualToData:[(@[@11, @12, @13, @14]) ows_toUint8Data]]);
}
-(void) testMutableDataReplaceBytesStartingAt {
    NSMutableData* d = [NSMutableData dataWithLength:6];
    NSData* d2 = [@[@1, @2, @3] ows_toUint8Data];
    testThrows([d replaceBytesStartingAt:0 withData:nil]);
    testThrows([d replaceBytesStartingAt:4 withData:d2]);
    
    [d replaceBytesStartingAt:0 withData:d2];
    test([d isEqualToData:[(@[@1, @2, @3, @0, @0, @0]) ows_toUint8Data]]);
    [d replaceBytesStartingAt:2 withData:d2];
    test([d isEqualToData:[(@[@1, @2, @1, @2, @3, @0]) ows_toUint8Data]]);
    [d replaceBytesStartingAt:3 withData:d2];
    test([d isEqualToData:[(@[@1, @2, @1, @1, @2, @3]) ows_toUint8Data]]);
}
-(void) testStringEncodedAsUtf8 {
    test([@"ab".encodedAsUtf8 isEqualToData:[(@[@97, @98]) ows_toUint8Data]]);
}
-(void) testStringEncodedAsAscii {
    test([@"ab".encodedAsAscii isEqualToData:[(@[@97, @98]) ows_toUint8Data]]);
    testThrows(@"√".encodedAsAscii);
}
-(void) testBase64EncodeKnown {
    test([@"".encodedAsUtf8.encodedAsBase64 isEqualToString:@""]);
    test([@"f".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zg=="]);
    test([@"fo".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zm8="]);
    test([@"foo".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zm9v"]);
    test([@"foob".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zm9vYg=="]);
    test([@"fooba".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zm9vYmE="]);
    test([@"foobar".encodedAsUtf8.encodedAsBase64 isEqualToString:@"Zm9vYmFy"]);
}
-(void) testBase64DecodeKnown {
    test([@"".encodedAsUtf8 isEqualToData:[@"" decodedAsBase64Data]]);
    test([@"f".encodedAsUtf8 isEqualToData:[@"Zg==" decodedAsBase64Data]]);
    test([@"fo".encodedAsUtf8 isEqualToData:[@"Zm8=" decodedAsBase64Data]]);
    test([@"foo".encodedAsUtf8 isEqualToData:[@"Zm9v" decodedAsBase64Data]]);
    test([@"foob".encodedAsUtf8 isEqualToData:[@"Zm9vYg==" decodedAsBase64Data]]);
    test([@"fooba".encodedAsUtf8 isEqualToData:[@"Zm9vYmE=" decodedAsBase64Data]]);
    test([@"foobar".encodedAsUtf8 isEqualToData:[@"Zm9vYmFy" decodedAsBase64Data]]);
}
-(void) testBase64Perturbed {
    for (NSUInteger i = 0; i < 100; i++) {
        uint32_t n = arc4random_uniform(10) + 10;
        uint8_t data[n];
        arc4random_buf(data, sizeof(data));
        NSData* d = [NSData dataWithBytes:data length:sizeof(data)];
        NSString* b = d.encodedAsBase64;
        NSData* d2 = [b decodedAsBase64Data];
        if (![d isEqualToData:d2]) {
            XCTFail(@"%@",[d description]);
        } 
    }
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
-(void) testToJson {
    test([@{}.encodedAsJson isEqualToString:@"{}"]);
    test([[@{@"a":@"b"} encodedAsJson] isEqualToString:@"{\"a\":\"b\"}"]);
    test([[@{@"c":@5} encodedAsJson] isEqualToString:@"{\"c\":5}"]);
    test([[(@{@"a":@5,@"b":@YES}) encodedAsJson] isEqualToString:@"{\"a\":5,\"b\":true}"]);
    
    testThrows([@{@"ev": @"a+b".toRegularExpression} encodedAsJson]);
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
-(void) testRepresentedAsHexString {
    test([[[NSData data] encodedAsHexString] isEqualToString:@""]);
    test([increasingData(17).encodedAsHexString isEqualToString:@"000102030405060708090a0b0c0d0e0f10"]);
    test([increasingDataFrom(256-16,16).encodedAsHexString isEqualToString:@"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"]);
}
-(void) testDecodedAsHexData {
    test([[@"" decodedAsHexString] isEqualToData:[NSData data]]);
    test([[@"000102030405060708090a0b0c0d0e0f10" decodedAsHexString] isEqualToData:increasingData(17)]);
    test([[@"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff" decodedAsHexString] isEqualToData:increasingDataFrom(256-16,16)]);
    testThrows([@"gg" decodedAsHexString]);
    testThrows([@"-1" decodedAsHexString]);
    testThrows([@"a" decodedAsHexString]);
    testThrows([@"-" decodedAsHexString]);
    testThrows([@"0" decodedAsHexString]);
}
-(void) testHasUnsignedIntegerValue {
    test((@0).hasUnsignedIntegerValue);
    test((@1).hasUnsignedIntegerValue);
    test((@0xFFFFFFFF).hasUnsignedIntegerValue);
    test(@(pow(2, 31)).hasUnsignedIntegerValue);
    test(!(@-1).hasUnsignedIntegerValue);
    test(!(@0.5).hasUnsignedIntegerValue);
}
-(void) testHasUnsignedLongLongValue {
    test((@0).hasUnsignedLongLongValue);
    test((@1).hasUnsignedLongLongValue);
    test((@0xFFFFFFFFFFFFFFFF).hasUnsignedLongLongValue);
    test(@(pow(2, 63)).hasUnsignedLongLongValue);
    test(!@(pow(2, 64)).hasUnsignedLongLongValue);
    test(!(@-1).hasUnsignedLongLongValue);
    test(!(@0.5).hasUnsignedLongLongValue);
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
