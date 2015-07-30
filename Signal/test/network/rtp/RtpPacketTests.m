#import <XCTest/XCTest.h>
#import "TestUtil.h"

@interface RtpPacketTests : XCTestCase

@end

@implementation RtpPacketTests

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
}

-(void) testRawDataSimple {
    RtpPacket* r = [RtpPacket rtpPacketWithVersion:2
                                        andPadding:0
                  andContributingSourceIdentifiers:@[]
                andSynchronizationSourceIdentifier:0
                                      andMarkerBit:false
                                    andPayloadtype:0
                                 andSequenceNumber:5
                                      andTimeStamp:0
                                        andPayload:increasingData(5)];
    
    // values were retained
    test([r version] == 2);
    test([r padding] == 0);
    test(r.hasExtensionHeader == false);
    test([[r contributingSourceIdentifiers] count] == 0);
    test([r synchronizationSourceIdentifier] == 0);
    test(r.isMarkerBitSet == false);
    test([r payloadType] == 0);
    test([r sequenceNumber] == 5);
    test([r timeStamp] == 0);
    test([[r payload] isEqualToData:increasingData(5)]);

    // equivalent to simplified constructor
    test([r isEqualToRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:5 andPayload:increasingData(5)]]);

    // packed correctly
    NSData* expectedData = [@[
                            @0x80,@0,@0,@5,
                            @0,@0,@0,@0,
                            @0,@0,@0,@0,
                            @0,@1,@2,@3,@4] ows_toUint8Data];
    test([[r rawPacketDataUsingInteropOptions:@[]] isEqualToData:expectedData]);

    // reparsing packed data gives same packet
    test([r isEqualToRtpPacket:[RtpPacket rtpPacketParsedFromPacketData:expectedData]]);
    test(![r isEqualToRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:0 andPayload:[NSData data]]]);
}
-(void) testRawData {
    RtpPacket* r = [RtpPacket rtpPacketWithVersion:2
                                        andPadding:3
                  andContributingSourceIdentifiers:@[@101, @102]
                andSynchronizationSourceIdentifier:0x45645645
                                      andMarkerBit:true
                                    andPayloadtype:0x77
                                 andSequenceNumber:0x2122
                                      andTimeStamp:0xABCDEFAB
                                        andPayload:increasingData(6)];

    // values were retained
    test([r version] == 2);
    test([r padding] == 3);
    test(r.hasExtensionHeader == false);
    test([[r contributingSourceIdentifiers] isEqualToArray:(@[@101, @102])]);
    test([r synchronizationSourceIdentifier] == 0x45645645);
    test(r.isMarkerBitSet == true);
    test([r payloadType] == 0x77);
    test([r sequenceNumber] == 0x2122);
    test([r timeStamp] == 0xABCDEFAB);
    test([[r payload] isEqualToData:increasingData(6)]);

    NSData* expectedData = [@[
                            @0xA2,@0xF7,@0x21,@0x22,
                            @0xAB,@0xCD,@0xEF,@0xAB,
                            @0x45,@0x64,@0x56,@0x45,
                            @0,@0,@0,@101,
                            @0,@0,@0,@102,
                            @0,@1,@2,@3,@4,@5,
                            @0,@0,@3] ows_toUint8Data];
    
    test([[r rawPacketDataUsingInteropOptions:@[]] isEqualToData:expectedData]);
    test([r isEqualToRtpPacket:[RtpPacket rtpPacketParsedFromPacketData:expectedData]]);
    test(![r isEqualToRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:90 andPayload:[NSData data]]]);
}
-(void) testExtendedData {
    RtpPacket* r = [RtpPacket rtpPacketWithVersion:2
                                        andPadding:0
                  andContributingSourceIdentifiers:@[]
                andSynchronizationSourceIdentifier:0
                            andExtensionIdentifier:0xFEAB
                                  andExtensionData:increasingDataFrom(10, 5)
                                      andMarkerBit:false
                                    andPayloadtype:0
                                 andSequenceNumber:5
                                      andTimeStamp:0
                                        andPayload:increasingData(5)];

    // values were retained
    test([r version] == 2);
    test([r padding] == 0);
    test(r.hasExtensionHeader == true);
    test([r extensionHeaderIdentifier] == 0xFEAB);
    test([[r extensionHeaderData] isEqualToData:increasingDataFrom(10, 5)]);
    test([[r contributingSourceIdentifiers] count] == 0);
    test([r synchronizationSourceIdentifier] == 0);
    test(r.isMarkerBitSet == false);
    test([r payloadType] == 0);
    test([r sequenceNumber] == 5);
    test([r timeStamp] == 0);
    test([[r payload] isEqualToData:increasingData(5)]);
    
    NSData* expectedData = [@[
                            @0x90,@0,@0,@5,
                            @0,@0,@0,@0,
                            @0,@0,@0,@0,
                            @0xFE,@0xAB,
                            @0, @5,
                            @10,@11,@12,@13,@14,
                            @0,@1,@2,@3,@4] ows_toUint8Data];
    test([[r rawPacketDataUsingInteropOptions:@[]] isEqualToData:expectedData]);
    test([r isEqualToRtpPacket:[RtpPacket rtpPacketParsedFromPacketData:expectedData]]);
    test(![r isEqualToRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:0 andPayload:[NSData data]]]);
}

@end
