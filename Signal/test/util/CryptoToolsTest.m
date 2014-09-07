#import <XCTest/XCTest.h>
#import "Util.h"
#import "CryptoTools.h"
#import "TestUtil.h"

@interface CryptoToolsTest : XCTestCase

@end

@implementation CryptoToolsTest
-(void) testIsEqualToData_TimingSafe {
    test([[NSMutableData dataWithLength:0] isEqualToData_TimingSafe:[NSMutableData dataWithLength:0]]);
    test([[NSMutableData dataWithLength:1] isEqualToData_TimingSafe:[NSMutableData dataWithLength:1]]);
    test(![[NSMutableData dataWithLength:1] isEqualToData_TimingSafe:[NSMutableData dataWithLength:0]]);
    test([[@"01020304" decodedAsHexString] isEqualToData_TimingSafe:[@"01020304" decodedAsHexString]]);
    test(![[@"01020305" decodedAsHexString] isEqualToData_TimingSafe:[@"01020304" decodedAsHexString]]);
    test(![[@"05020305" decodedAsHexString] isEqualToData_TimingSafe:[@"01020304" decodedAsHexString]]);
    test(![[@"05020304" decodedAsHexString] isEqualToData_TimingSafe:[@"01020304" decodedAsHexString]]);
    test(![[@"01050304" decodedAsHexString] isEqualToData_TimingSafe:[@"01020304" decodedAsHexString]]);
}
-(void) testKnownHmacSha1 {
    char* keyText = "key";
    char* valText = "The quick brown fox jumps over the lazy dog";
    NSData* key = [NSMutableData dataWithBytes:keyText length:strlen(keyText)];
    NSData* val = [NSMutableData dataWithBytes:valText length:strlen(valText)];
    NSData* expected = [@"de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9" decodedAsHexString];
    NSData* actual = [val hmacWithSha1WithKey:key];
    test([actual isEqualToData:expected]);
}
-(void) testKnownHmacSha256 {
    char* keyText = "key";
    char* valText = "The quick brown fox jumps over the lazy dog";
    NSData* key = [NSMutableData dataWithBytes:keyText length:strlen(keyText)];
    NSData* val = [NSMutableData dataWithBytes:valText length:strlen(valText)];
    NSData* expected = [@"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8" decodedAsHexString];
    NSData* actual = [val hmacWithSha256WithKey:key];
    test([actual isEqualToData:expected]);
}
-(void) testAesCipherBlockChainingPadding {
    NSData* iv = [@"000102030405060708090A0B0C0D0E0F" decodedAsHexString];
    NSData* plain =[@"10b80d8098f0283a820e" decodedAsHexString];
    NSData* key =[@"2b7e151628aed2a6abf7158809cf4f3c" decodedAsHexString];
    
    NSData* cipher = [plain encryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:key andIv:iv];
    test(cipher.length % 16 == 0);
    NSData* replain = [cipher decryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:key andIv:iv];
    test(plain.length == replain.length);
}
-(void) testKnownSha256 {
    char* valText = "The quick brown fox jumps over the lazy dog";
    NSData* val = [NSMutableData dataWithBytes:valText length:strlen(valText)];
    NSData* expected = [@"d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592" decodedAsHexString];
    NSData* actual = [val hashWithSha256];
    test([actual isEqualToData:expected]);
}
-(void) testRandomForVariance {
    NSData* d = [CryptoTools generateSecureRandomData:8];
    NSData* d2 = [CryptoTools generateSecureRandomData:8];
    
    test(5 == [[CryptoTools generateSecureRandomData:5] length]);
    test(8 == d.length);
    
    // extremely unlikely to fail if any reasonable amount of entropy is going into d and d2
    test(![d isEqualToData:d2]);
}

-(void) testRandomUInt16GenerationForVariance{
    uint16_t a = [CryptoTools generateSecureRandomUInt16];
    uint16_t b = [CryptoTools generateSecureRandomUInt16];
    uint16_t c = [CryptoTools generateSecureRandomUInt16];
    uint16_t d = [CryptoTools generateSecureRandomUInt16];

    // extremely unlikely to fail if any reasonable amount of entropy is generated
    BOOL same =((a==b) && (a==c) && (a==d));
    test (!same);
}

-(void) testGenerateSecureRandomUInt32_varies {
    NSMutableSet* s = [NSMutableSet new];
    
    for (uint i = 0; i < 10; i++) {
        [s addObject:@([CryptoTools generateSecureRandomUInt32])];
    }
    
    // Note: expected false negative rate is approximately once per hundred million runs
    test(s.count == 10);
}

-(void) testKnownAesCipherFeedback {
    NSData* iv = [@"000102030405060708090a0b0c0d0e0f" decodedAsHexString];
    NSData* plain =[@"6bc1bee22e409f96e93d7e117393172a" decodedAsHexString];
    NSData* cipher =[@"3b3fd92eb72dad20333449f8e83cfb4a" decodedAsHexString];
    NSData* key =[@"2b7e151628aed2a6abf7158809cf4f3c" decodedAsHexString];

    test([[plain encryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:cipher]);
    test([[cipher decryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:plain]);
}
-(void) testPerturbedAesCipherFeedbackInverts {
    for (int repeat = 0; repeat < 100; repeat++) {
        NSData* iv = generatePseudoRandomData(16);
        NSData* input = generatePseudoRandomData(16);
        NSData* key = generatePseudoRandomData(16);
        
        test([[[input encryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] decryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:input]);
        test([[[input decryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] encryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:input]);
    }
}

-(void) testKnownAesCounter {
    NSData* iv = [@"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff" decodedAsHexString];
    NSData* plain =[@"6bc1bee22e409f96e93d7e117393172a" decodedAsHexString];
    NSData* cipher =[@"874d6191b620e3261bef6864990db6ce" decodedAsHexString];
    NSData* key =[@"2b7e151628aed2a6abf7158809cf4f3c" decodedAsHexString];
    
    test([[plain encryptWithAesInCounterModeWithKey:key andIv:iv] isEqualToData:cipher]);
    test([[cipher decryptWithAesInCounterModeWithKey:key andIv:iv] isEqualToData:plain]);
}
-(void) testAesCounterEndianness {
    NSData* iv = [@"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff" decodedAsHexString];
    NSData* plain =[@"6bc1bee22e409f96e93d7e117393172ab1661dadd153b245034f1fb3655dc560" decodedAsHexString];
    NSData* cipher =[@"874d6191b620e3261bef6864990db6ce874d6191b620e3261bef6864990db6ce" decodedAsHexString];
    NSData* key =[@"2b7e151628aed2a6abf7158809cf4f3c" decodedAsHexString];
    
    test([[plain encryptWithAesInCounterModeWithKey:key andIv:iv] isEqualToData:cipher]);
    test([[cipher decryptWithAesInCounterModeWithKey:key andIv:iv] isEqualToData:plain]);
}
-(void) testPerturbedAesCounterInverts {
    for (int repeat = 0; repeat < 100; repeat++) {
        NSData* iv = generatePseudoRandomData(16);
        NSData* input = generatePseudoRandomData(16);
        NSData* key = generatePseudoRandomData(16);
        
        test([[[input encryptWithAesInCounterModeWithKey:key andIv:iv] decryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:input]);
        test([[[input decryptWithAesInCounterModeWithKey:key andIv:iv] encryptWithAesInCipherFeedbackModeWithKey:key andIv:iv] isEqualToData:input]);
    }
}
-(void) testComputeKnownOtp {
    test([[CryptoTools computeOtpWithPassword:@"password" andCounter:123] isEqualToString:@"SiYZc8Xg6KSmCECSImVSmjnRNfc="]);
}

@end
