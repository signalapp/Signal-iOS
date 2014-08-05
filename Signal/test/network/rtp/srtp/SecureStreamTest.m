#import <XCTest/XCTest.h>
#import "SrtpStream.h"
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
        SrtpStream* ss = [SrtpStream srtpStreamWithCipherKey:key andMacKey:macKey andCipherIvSalt:salt];
        
        for (uint64_t sequenceNumber = 0; sequenceNumber < 0x70000; sequenceNumber += 0x7000) {
            RtpPacket* r = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:(uint16_t)(sequenceNumber & 0xFFFF) andPayload:generatePseudoRandomData(12)];
            RtpPacket* s = [ss encryptAndAuthenticateNormalRtpPacket:r];
            RtpPacket* r2 = [ss verifyAuthenticationAndDecryptSecuredRtpPacket:s];
            test(![r isEqualToRtpPacket:s]);
            test([r isEqualToRtpPacket:r2]);
        }
    }
}
-(void) testReject {
    NSData* key = generatePseudoRandomData(16);
    NSData* macKey = generatePseudoRandomData(16);
    NSData* salt = generatePseudoRandomData(14);
    SrtpStream* ss = [SrtpStream srtpStreamWithCipherKey:key andMacKey:macKey andCipherIvSalt:salt];
    
    // fuzzing
    testThrows([ss verifyAuthenticationAndDecryptSecuredRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(0)]]);
    testThrows([ss verifyAuthenticationAndDecryptSecuredRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(12)]]);
    testThrows([ss verifyAuthenticationAndDecryptSecuredRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:0 andPayload:generatePseudoRandomData(100)]]);

    // authenticated then bit flip
    RtpPacket* r = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:5 andPayload:generatePseudoRandomData(40)];
    RtpPacket* s = [ss encryptAndAuthenticateNormalRtpPacket:r];
    NSMutableData* m = [[s payload] mutableCopy];
    [m setUint8At:0 to:[m uint8At:0]^1];
    RtpPacket* sm = [r withPayload:m];
    testThrows([ss verifyAuthenticationAndDecryptSecuredRtpPacket:sm]);
}

-(void) testCannotDesyncExtendedSequenceNumberWithInjectedSequenceNumbers {
    NSData* key = generatePseudoRandomData(16);
    NSData* macKey = generatePseudoRandomData(16);
    NSData* salt = generatePseudoRandomData(14);
    SrtpStream* s1 = [SrtpStream srtpStreamWithCipherKey:key andMacKey:macKey andCipherIvSalt:salt];
    SrtpStream* s2 = [SrtpStream srtpStreamWithCipherKey:key andMacKey:macKey andCipherIvSalt:salt];

    for (NSUInteger i = 0; i < 0x20000; i+= 0x100) {
        RtpPacket* m = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:(uint16_t)(i  & 0xFFFF) andPayload:generatePseudoRandomData(40)];
        testThrows([s1 verifyAuthenticationAndDecryptSecuredRtpPacket:m]);
    }
    
    RtpPacket* r = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:5 andPayload:generatePseudoRandomData(40)];
    RtpPacket* s = [s2 encryptAndAuthenticateNormalRtpPacket:r];
    RtpPacket* r2 = [s1 verifyAuthenticationAndDecryptSecuredRtpPacket:s];
    test([r isEqualToRtpPacket:r2]);
}

@end
