#import <XCTest/XCTest.h>
#import "HelloPacket.h"
#import "TestUtil.h"

@interface HandshakePacketTest : XCTestCase

@end

@implementation HandshakePacketTest

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
}

-(void) testHelloPacket {
    [Environment setCurrent:testEnv];
    HashChain* h = [HashChain hashChainWithSeed:[NSData dataWithLength:32]];
    HelloPacket* p = [HelloPacket helloPacketWithVersion:@"1.10".encodedAsUtf8
                                             andClientId:@"RedPhone 019    ".encodedAsAscii
                                          andHashChainH3:[h h3]
                                                  andZid:[Zid zidWithData:increasingData(12)]
                                            andFlags0SMP:0
                                      andFlagsUnusedLow4:0
                                     andFlagsUnusedHigh4:0
                                          andHashSpecIds:@[]
                                        andCipherSpecIds:@[]
                                          andAuthSpecIds:@[]
                                         andAgreeSpecIds:@[]
                                           andSasSpecIds:@[]
                                authenticatedWithHmacKey:[h h2]];
    NSData* data = [[[p embeddedIntoHandshakePacket] embeddedIntoRtpPacketWithSequenceNumber:0x25 usingInteropOptions:@[]] rawPacketDataUsingInteropOptions:@[]];
    uint8_t expectedData[] = {
        0x10,0x0,
        0x00,0x25, // sequence number
        0x5a,0x52,0x54,0x50, //timestamp: 'ZRTP'
        0,0,0,0, // source identifier
            0x50,0x5A, // extension type = 'PZ', 01010000 01011010
            0x00,88, // extension length =
            0x48,0x65,0x6C,0x6C,0x6F,0x20,0x20,0x20, //type: "Hello    "
            0x31,0x2E,0x31,0x30, //version: "1.10"
            0x52,0x65,0x64,0x50,0x68,0x6F,0x6E,0x65,0x20,0x30,0x31,0x39,0x20,0x20,0x20,0x20, // client id: "RedPhone 019    "
            0x12,0x77,0x13,0x55,0xe4,0x6c,0xd4,0x7c,0x71,0xed,0x17,0x21,0xfd,0x53,0x19,0xb3,0x83,0xcc,0xa3,0xa1,0xf9,0xfc,0xe3,0xaa,0x1c,0x8c,0xd3,0xbd,0x37,0xaf,0x20,0xd7, // h3
            0,1,2,3,4,5,6,7,8,9,10,11, // ZID
            0,0,0,0, // unused flags and counts
            0x4c,0xbd,0x3e,0xc7,0x2c,0x74,0xce,0xea, //mac
        0xd5,0xdd,0x9d,0x8e //crc
    };
    test([data isEqualToData:[NSData dataWithBytes:expectedData length:sizeof(expectedData)]]);
}

-(void) testLegacyHelloPacket {
    [Environment setCurrent:testEnvWith(ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER)];
    HashChain* h = [HashChain hashChainWithSeed:[NSData dataWithLength:32]];
    uint8_t legacySpecifiedData_raw[] = {
        0x20,0x0, // <-- wrong flag
        0x00,0x25, // sequence number
        0x5a,0x52,0x54,0x50, //timestamp: 'ZRTP'
        0,0,0,0, // source identifier
        0,0,0,0,0,0,0,0,0,0,0,0, // <-- incorrect zeroes between header and message
        0x50,0x5A, // extension type = 'PZ', 01010000 01011010
        0x00,88, // extension length =
        0x48,0x65,0x6C,0x6C,0x6F,0x20,0x20,0x20, //type: "Hello    "
        0x31,0x2E,0x31,0x30, //version: "1.10"
        0x52,0x65,0x64,0x50,0x68,0x6F,0x6E,0x65,0x20,0x30,0x31,0x39,0x20,0x20,0x20,0x20, // client id: "RedPhone 019    "
        0x12,0x77,0x13,0x55,0xe4,0x6c,0xd4,0x7c,0x71,0xed,0x17,0x21,0xfd,0x53,0x19,0xb3,0x83,0xcc,0xa3,0xa1,0xf9,0xfc,0xe3,0xaa,0x1c,0x8c,0xd3,0xbd,0x37,0xaf,0x20,0xd7, // h3
        0,1,2,3,4,5,6,7,8,9,10,11, // ZID
        0,0,0,0, // unused flags and counts
        0x4c,0xbd,0x3e,0xc7,0x2c,0x74,0xce,0xea, //mac
        0xf5,0xd9,0xea,0xdd //crc
    };
    NSData* legacySpecifiedData = [NSData dataWithBytes:legacySpecifiedData_raw length:sizeof(legacySpecifiedData_raw)];

    RtpPacket* rtp = [RtpPacket rtpPacketParsedFromPacketData:legacySpecifiedData];
    HelloPacket* p = [HelloPacket helloPacketParsedFromHandshakePacket:[HandshakePacket handshakePacketParsedFromRtpPacket:rtp]];
    [p verifyMacWithHashChainH2:h.h2];
    test(rtp.wasAdjustedDueToInteropIssues);
    test([p.hashChainH3 isEqual:h.h3]);
    test([p.clientId isEqual:@"RedPhone 019    ".encodedAsAscii]);
}
-(void) testHandshakeMacAuthenticationSucceeds{
    NSData* type = [@"0f0f0f0f0f0f0f0f" decodedAsHexString];
    NSData* payload =[@"ff00ff00" decodedAsHexString];
    NSData* untouchedPayload =[@"ff00ff00" decodedAsHexString];
    
    NSData* key =[@"11" decodedAsHexString];
    
    HandshakePacket* p = [HandshakePacket handshakePacketWithTypeId:type
                                                         andPayload:payload];
    HandshakePacket* withHMAC = [p withHmacAppended:key];
    HandshakePacket* strippedOfValidHMAC = [withHMAC withHmacVerifiedAndRemoved:key];
    
    test([[p payload] isEqualToData:[strippedOfValidHMAC payload]]);
    
    test([untouchedPayload isEqualToData:[p payload]]);
    test([untouchedPayload isEqualToData:[strippedOfValidHMAC payload]]);
}
-(void) testHandshakeMacAuthenticationFails{
    NSData* type = [@"0f0f0f0f0f0f0f0f" decodedAsHexString];
    NSData* payload =[@"ff00ff00" decodedAsHexString];
    NSData* untouchedPayload =[@"ff00ff00" decodedAsHexString];
    
    NSData* key =[@"11" decodedAsHexString];
    
    NSData* badkey =[@"10" decodedAsHexString];
    
    
    HandshakePacket* p = [HandshakePacket handshakePacketWithTypeId:type
                                                         andPayload:payload];
    HandshakePacket* withHMAC = [p withHmacAppended:key];
    
    testThrows([withHMAC withHmacVerifiedAndRemoved:badkey]);
    
    HandshakePacket* strippedOfValidHMAC = [withHMAC withHmacVerifiedAndRemoved:key];
    
    test([[p payload] isEqualToData:[strippedOfValidHMAC payload]]);
    
    test([untouchedPayload isEqualToData:[p payload]]);
    test([untouchedPayload isEqualToData:[strippedOfValidHMAC payload]]);
    
}
@end
