#import "HandshakePacket.h"
#import "DhPacket.h"
#import "ConfirmPacket.h"
#import "CommitPacket.h"
#import "ConfirmAckPacket.h"
#import "HelloAckPacket.h"

#define HANDSHAKE_PACKET_EXTENSION_IDENTIFIER [@"PZ".encodedAsAscii bigEndianUInt16At:0]
#define HANDSHAKE_PACKET_TIMESTAMP_COOKIE [@"ZRTP".encodedAsAscii bigEndianUInt32At:0]

#define HANDSHAKE_TYPE_ID_LENGTH 8
#define HANDSHAKE_CRC_LENGTH 4

#define HEADER_FOOTER_LENGTH_WITHOUT_HMAC (HANDSHAKE_TYPE_ID_LENGTH + HANDSHAKE_CRC_LENGTH)
#define HEADER_FOOTER_LENGTH_WITH_HMAC (HANDSHAKE_TYPE_ID_LENGTH + HANDSHAKE_CRC_LENGTH + HANDSHAKE_TRUNCATED_HMAC_LENGTH)

@implementation HandshakePacket

@synthesize payload, typeId;

+(HandshakePacket*) handshakePacketWithTypeId:(NSData*)typeId andPayload:(NSData*)payload {
    ows_require(typeId != nil);
    ows_require(payload != nil);
    ows_require(typeId.length == HANDSHAKE_TYPE_ID_LENGTH);
    
    HandshakePacket* p = [HandshakePacket new];
    p->typeId = typeId;
    p->payload = payload;
    return p;
}

+(NSData*) getHandshakeTypeIdFromRtp:(RtpPacket*)rtpPacket {
    return [[rtpPacket extensionHeaderData] take:HANDSHAKE_TYPE_ID_LENGTH];
}
+(NSData*) getHandshakePayloadFromRtp:(RtpPacket*)rtpPacket {
    return [[[rtpPacket extensionHeaderData] skip:HANDSHAKE_TYPE_ID_LENGTH] skipLast:HANDSHAKE_CRC_LENGTH];
}
+(uint32_t) getIncludedHandshakeCrcFromRtp:(RtpPacket*)rtpPacket {
    return [[[rtpPacket extensionHeaderData] takeLast:HANDSHAKE_CRC_LENGTH] bigEndianUInt32At:0];
}
+(HandshakePacket*) handshakePacketParsedFromRtpPacket:(RtpPacket*)rtpPacket {
    ows_require(rtpPacket != nil);
    checkOperation([rtpPacket timeStamp] == HANDSHAKE_PACKET_TIMESTAMP_COOKIE);
    checkOperation([rtpPacket version] == 0);
    checkOperation(rtpPacket.hasExtensionHeader);
    checkOperation([rtpPacket extensionHeaderIdentifier] == HANDSHAKE_PACKET_EXTENSION_IDENTIFIER);
    checkOperation([[rtpPacket extensionHeaderData] length] >= HEADER_FOOTER_LENGTH_WITHOUT_HMAC);
    
    NSData* handshakeTypeId = [self getHandshakeTypeIdFromRtp:rtpPacket];
    NSData* handshakePayload = [self getHandshakePayloadFromRtp:rtpPacket];
    uint32_t includedCrc = [self getIncludedHandshakeCrcFromRtp:rtpPacket];
    
    HandshakePacket* p = [HandshakePacket new];
    p->typeId = handshakeTypeId;
    p->payload = handshakePayload;
    
    uint32_t expectedCrc = [[[rtpPacket rawPacketDataUsingInteropOptions:nil] skipLastVolatile:4] crc32];
    checkOperation(includedCrc == expectedCrc);
    
    return p;
}

-(HandshakePacket*) withHmacAppended:(NSData*)macKey {
    ows_require(macKey != nil);
    NSData* digest = [[[self rtpExtensionPayloadUsedForHmacBeforeHmacAppended] hmacWithSha256WithKey:macKey] take:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    NSData* authenticatedPayload = [@[payload, digest] ows_concatDatas];
    return [HandshakePacket handshakePacketWithTypeId:typeId andPayload:authenticatedPayload];
}
-(HandshakePacket*) withHmacVerifiedAndRemoved:(NSData*)macKey {
    ows_require(macKey != nil);
    
    NSData* authenticatedData = [self rtpExtensionHeaderAndPayloadExceptCrc];
    
    NSData* expectedHmac = [[[authenticatedData skipLastVolatile:HANDSHAKE_TRUNCATED_HMAC_LENGTH] hmacWithSha256WithKey:macKey] take:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    NSData* includedHmac = [authenticatedData takeLastVolatile:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    
    checkOperation([expectedHmac isEqualToData_TimingSafe:includedHmac]);
    
    return [HandshakePacket handshakePacketWithTypeId:typeId andPayload:[payload skipLast:HANDSHAKE_TRUNCATED_HMAC_LENGTH]];
}

-(NSData*)dataUsedForAuthentication {
    return [self rtpExtensionHeaderAndPayloadExceptCrc];
}

-(NSData*) rtpExtensionHeaderAndPayloadExceptCrc {
    // The data corresponding to the rtp extension header is used when hmac-ing
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)(payload.length + HEADER_FOOTER_LENGTH_WITHOUT_HMAC)],
            typeId,
            payload
            ] ows_concatDatas];
}

-(NSData*) rtpExtensionPayloadExceptCrc {
    return [@[
            typeId,
            payload
            ] ows_concatDatas];
}

-(NSData*) rtpExtensionPayloadUsedForHmacBeforeHmacAppended {
    // When we hmac the rtp extension header, the hmac length must be counted even though it's not appended yet
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)(payload.length + HEADER_FOOTER_LENGTH_WITH_HMAC)],
            typeId,
            payload
            ] ows_concatDatas];
}

-(RtpPacket*) embeddedIntoRtpPacketWithSequenceNumber:(uint16_t)sequenceNumber usingInteropOptions:(NSArray*)interopOptions {
    requireState(typeId.length == HANDSHAKE_TYPE_ID_LENGTH);
    
    NSData* payloadExceptCrc = [self rtpExtensionPayloadExceptCrc];
    NSData* extensionDataWithZeroCrc = [(@[payloadExceptCrc, [NSData dataWithBigEndianBytesOfUInt32:0]]) ows_concatDatas];
    RtpPacket* packetWithZeroCrc = [RtpPacket rtpPacketWithVersion:0 // invalid version 0 indicates a zrtp handshake packet
                                                       andPadding:false
                                 andContributingSourceIdentifiers:@[]
                               andSynchronizationSourceIdentifier:0
                                           andExtensionIdentifier:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER
                                                 andExtensionData:extensionDataWithZeroCrc
                                                     andMarkerBit:false
                                                   andPayloadtype:0
                                                andSequenceNumber:sequenceNumber
                                                     andTimeStamp:HANDSHAKE_PACKET_TIMESTAMP_COOKIE
                                                       andPayload:[NSData data]];

    uint32_t crc = [[[packetWithZeroCrc rawPacketDataUsingInteropOptions:interopOptions] skipLastVolatile:4] crc32];
    NSData* extensionData = [(@[payloadExceptCrc, [NSData dataWithBigEndianBytesOfUInt32:crc]]) ows_concatDatas];
    
    return [RtpPacket rtpPacketWithVersion:0 // invalid version 0 indicates a zrtp handshake packet
                                andPadding:false
          andContributingSourceIdentifiers:@[]
        andSynchronizationSourceIdentifier:0
                    andExtensionIdentifier:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER
                          andExtensionData:extensionData
                              andMarkerBit:false
                            andPayloadtype:0
                         andSequenceNumber:sequenceNumber
                              andTimeStamp:HANDSHAKE_PACKET_TIMESTAMP_COOKIE
                                andPayload:[NSData data]];
}

-(HelloPacket*) parsedAsHello {
    return [HelloPacket helloPacketParsedFromHandshakePacket:self];
}
-(HelloAckPacket*) parsedAsHelloAck {
    return [HelloAckPacket helloAckPacketParsedFromHandshakePacket:self];
}
-(CommitPacket*) parsedAsCommitPacket {
    return [CommitPacket commitPacketParsedFromHandshakePacket:self];
}
-(DhPacket*) parsedAsDh1 {
    return [DhPacket dhPacketFromHandshakePacket:self andIsPart1:true];
}
-(DhPacket*) parsedAsDh2 {
    return [DhPacket dhPacketFromHandshakePacket:self andIsPart1:false];
}
-(ConfirmPacket*) parsedAsConfirm1AuthenticatedWithMacKey:(NSData*)macKey andCipherKey:(NSData*)cipherKey {
    return [ConfirmPacket confirmPacketParsedFromHandshakePacket:self
                                                      withMacKey:macKey
                                                    andCipherKey:cipherKey
                                                      andIsPart1:true];
}
-(ConfirmPacket*) parsedAsConfirm2AuthenticatedWithMacKey:(NSData*)macKey andCipherKey:(NSData*)cipherKey {
    return [ConfirmPacket confirmPacketParsedFromHandshakePacket:self
                                                      withMacKey:macKey
                                                    andCipherKey:cipherKey
                                                      andIsPart1:false];
}
-(ConfirmAckPacket*) parsedAsConfAck {
    return [ConfirmAckPacket confirmAckPacketParsedFromHandshakePacket:self];
}

-(NSString*) description {
    return [NSString stringWithFormat:@"Handshake: %@", [[self typeId] decodedAsAsciiReplacingErrorsWithDots]];
}

@end
