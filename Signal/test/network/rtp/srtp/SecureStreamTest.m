#import <XCTest/XCTest.h>
#import "SRTPStream.h"
#import "Util.h"
#import "TestUtil.h"

@interface SecureStreamTest : XCTestCase

@end

@implementation SecureStreamTest

-(void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
}

-(void) testPerturbedRoundTrip {
    for (int repeat = 0; repeat < 10; repeat++) {
        NSData* key = generatePseudoRandomData(16);
        NSData* macKey = generatePseudoRandomData(16);
        NSData* salt = generatePseudoRandomData(14);
        SRTPStream* ss = [[SRTPStream alloc] initWithCipherKey:key andMacKey:macKey andCipherIVSalt:salt];
        
        for (uint64_t sequenceNumber = 0; sequenceNumber < 0x70000; sequenceNumber += 0x7000) {
            RTPPacket* r = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:(uint16_t)(sequenceNumber & 0xFFFF) andPayload:generatePseudoRandomData(12)];
            RTPPacket* s = [ss encryptAndAuthenticateNormalRTPPacket:r];
            RTPPacket* r2 = [ss verifyAuthenticationAndDecryptSecuredRTPPacket:s];
            test(![r isEqualToRTPPacket:s]);
            test([r isEqualToRTPPacket:r2]);
        }
    }
}
-(void) testReject {
    NSData* key = generatePseudoRandomData(16);
    NSData* macKey = generatePseudoRandomData(16);
    NSData* salt = generatePseudoRandomData(14);
    SRTPStream* ss = [[SRTPStream alloc] initWithCipherKey:key andMacKey:macKey andCipherIVSalt:salt];
    
    // fuzzing
    testThrows([ss verifyAuthenticationAndDecryptSecuredRTPPacket:[[RTPPacket alloc] initWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(0)]]);
    testThrows([ss verifyAuthenticationAndDecryptSecuredRTPPacket:[[RTPPacket alloc] initWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(12)]]);
    testThrows([ss verifyAuthenticationAndDecryptSecuredRTPPacket:[[RTPPacket alloc] initWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(100)]]);

    // authenticated then bit flip
    RTPPacket* r = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:5 andPayload:generatePseudoRandomData(40)];
    RTPPacket* s = [ss encryptAndAuthenticateNormalRTPPacket:r];
    NSMutableData* m = [[s payload] mutableCopy];
    [m setUint8At:0 to:[m uint8At:0]^1];
    RTPPacket* sm = [r withPayload:m];
    testThrows([ss verifyAuthenticationAndDecryptSecuredRTPPacket:sm]);
}

-(void) testCannotDesyncExtendedSequenceNumberWithInjectedSequenceNumbers {
    NSData* key = generatePseudoRandomData(16);
    NSData* macKey = generatePseudoRandomData(16);
    NSData* salt = generatePseudoRandomData(14);
    SRTPStream* s1 = [[SRTPStream alloc] initWithCipherKey:key andMacKey:macKey andCipherIVSalt:salt];
    SRTPStream* s2 = [[SRTPStream alloc] initWithCipherKey:key andMacKey:macKey andCipherIVSalt:salt];

    for (NSUInteger i = 0; i < 0x20000; i+= 0x100) {
        RTPPacket* m = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:(uint16_t)(i  & 0xFFFF) andPayload:generatePseudoRandomData(40)];
        testThrows([s1 verifyAuthenticationAndDecryptSecuredRTPPacket:m]);
    }
    
    RTPPacket* r = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:5 andPayload:generatePseudoRandomData(40)];
    RTPPacket* s = [s2 encryptAndAuthenticateNormalRTPPacket:r];
    RTPPacket* r2 = [s1 verifyAuthenticationAndDecryptSecuredRTPPacket:s];
    test([r isEqualToRTPPacket:r2]);
}

@end
