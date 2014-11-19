#import "HandshakePacket.h"
#import "Constraints.h"
#import "NSData+Conversions.h"
#import "Util.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "NSData+CRC.h"
#import "DHPacket.h"
#import "ConfirmPacket.h"
#import "CommitPacket.h"
#import "HelloPacket.h"
#import "ConfirmAckPacket.h"
#import "HelloAckPacket.h"

#define HANDSHAKE_PACKET_EXTENSION_IDENTIFIER [@"PZ".encodedAsAscii bigEndianUInt16At:0]
#define HANDSHAKE_PACKET_TIMESTAMP_COOKIE [@"ZRTP".encodedAsAscii bigEndianUInt32At:0]

#define HANDSHAKE_TYPE_ID_LENGTH 8
#define HANDSHAKE_CRC_LENGTH 4

#define HEADER_FOOTER_LENGTH_WITHOUT_HMAC (HANDSHAKE_TYPE_ID_LENGTH + HANDSHAKE_CRC_LENGTH)
#define HEADER_FOOTER_LENGTH_WITH_HMAC (HANDSHAKE_TYPE_ID_LENGTH + HANDSHAKE_CRC_LENGTH + HANDSHAKE_TRUNCATED_HMAC_LENGTH)

@interface HandshakePacket ()

@property (strong, readwrite, nonatomic) NSData* typeId;
@property (strong, readwrite, nonatomic) NSData* payload;

@end

@implementation HandshakePacket

- (instancetype)initWithTypeId:(NSData*)typeId andPayload:(NSData*)payload {
    if (self = [super init]) {
        require(typeId != nil);
        require(payload != nil);
        require(typeId.length == HANDSHAKE_TYPE_ID_LENGTH);
        
        self.typeId = typeId;
        self.payload = payload;
    }
    
    return self;
}

- (NSData*)getHandshakeTypeIdFromRtp:(RTPPacket*)rtpPacket {
    return [[rtpPacket extensionHeaderData] take:HANDSHAKE_TYPE_ID_LENGTH];
}

- (NSData*)getHandshakePayloadFromRtp:(RTPPacket*)rtpPacket {
    return [[[rtpPacket extensionHeaderData] skip:HANDSHAKE_TYPE_ID_LENGTH] skipLast:HANDSHAKE_CRC_LENGTH];
}

- (uint32_t)getIncludedHandshakeCrcFromRtp:(RTPPacket*)rtpPacket {
    return [[[rtpPacket extensionHeaderData] takeLast:HANDSHAKE_CRC_LENGTH] bigEndianUInt32At:0];
}

- (instancetype)initFromRTPPacket:(RTPPacket*)rtpPacket {
    if (self = [super init]) {
        require(rtpPacket != nil);
        checkOperation([rtpPacket timeStamp] == HANDSHAKE_PACKET_TIMESTAMP_COOKIE);
        checkOperation([rtpPacket version] == 0);
        checkOperation(rtpPacket.hasExtensionHeader);
        checkOperation([rtpPacket extensionHeaderIdentifier] == HANDSHAKE_PACKET_EXTENSION_IDENTIFIER);
        checkOperation([[rtpPacket extensionHeaderData] length] >= HEADER_FOOTER_LENGTH_WITHOUT_HMAC);
        
        NSData* handshakeTypeId  = [self getHandshakeTypeIdFromRtp:rtpPacket];
        NSData* handshakePayload = [self getHandshakePayloadFromRtp:rtpPacket];
        uint32_t includedCrc     = [self getIncludedHandshakeCrcFromRtp:rtpPacket];
        
        self.typeId = handshakeTypeId;
        self.payload = handshakePayload;
        
        uint32_t expectedCrc = [[[rtpPacket rawPacketDataUsingInteropOptions:nil] skipLastVolatile:4] crc32];
        checkOperation(includedCrc == expectedCrc);
    }
    
    return self;
}

- (HandshakePacket*)withHMACAppended:(NSData*)macKey {
    require(macKey != nil);
    NSData* digest = [[[self rtpExtensionPayloadUsedForHMACBeforeHMACAppended] hmacWithSHA256WithKey:macKey] take:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    NSData* authenticatedPayload = [@[self.payload, digest] concatDatas];
    return [[HandshakePacket alloc] initWithTypeId:self.typeId andPayload:authenticatedPayload];
}

- (HandshakePacket*)withHMACVerifiedAndRemoved:(NSData*)macKey {
    require(macKey != nil);
    
    NSData* authenticatedData = [self rtpExtensionHeaderAndPayloadExceptCRC];
    
    NSData* expectedHMAC = [[[authenticatedData skipLastVolatile:HANDSHAKE_TRUNCATED_HMAC_LENGTH] hmacWithSHA256WithKey:macKey] take:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    NSData* includedHMAC = [authenticatedData takeLastVolatile:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
    
    checkOperation([expectedHMAC isEqualToData_TimingSafe:includedHMAC]);
    
    return [[HandshakePacket alloc] initWithTypeId:self.typeId andPayload:[self.payload skipLast:HANDSHAKE_TRUNCATED_HMAC_LENGTH]];
}

- (NSData*)dataUsedForAuthentication {
    return [self rtpExtensionHeaderAndPayloadExceptCRC];
}

- (NSData*)rtpExtensionHeaderAndPayloadExceptCRC {
    // The data corresponding to the rtp extension header is used when hmac-ing
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)(self.payload.length + HEADER_FOOTER_LENGTH_WITHOUT_HMAC)],
            self.typeId,
            self.payload
            ] concatDatas];
}

- (NSData*)rtpExtensionPayloadExceptCRC {
    return [@[
            self.typeId,
            self.payload
            ] concatDatas];
}

- (NSData*)rtpExtensionPayloadUsedForHMACBeforeHMACAppended {
    // When we hmac the rtp extension header, the hmac length must be counted even though it's not appended yet
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:HANDSHAKE_PACKET_EXTENSION_IDENTIFIER],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)(self.payload.length + HEADER_FOOTER_LENGTH_WITH_HMAC)],
            self.typeId,
            self.payload
            ] concatDatas];
}

- (RTPPacket*)embeddedIntoRTPPacketWithSequenceNumber:(uint16_t)sequenceNumber
                                  usingInteropOptions:(NSArray*)interopOptions {
    requireState(self.typeId.length == HANDSHAKE_TYPE_ID_LENGTH);
    
    NSData* payloadExceptCrc = [self rtpExtensionPayloadExceptCRC];
    NSData* extensionDataWithZeroCrc = [(@[payloadExceptCrc, [NSData dataWithBigEndianBytesOfUInt32:0]]) concatDatas];
    RTPPacket* packetWithZeroCrc = [[RTPPacket alloc] initWithVersion:0 // invalid version 0 indicates a zrtp handshake packet
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
    NSData* extensionData = [(@[payloadExceptCrc, [NSData dataWithBigEndianBytesOfUInt32:crc]]) concatDatas];
    
    return [[RTPPacket alloc] initWithVersion:0 // invalid version 0 indicates a zrtp handshake packet
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

- (HelloPacket*)parsedAsHello {
    return [[HelloPacket alloc] initFromHandshakePacket:self];
}

- (HelloAckPacket*)parsedAsHelloAck {
    return [[HelloAckPacket alloc] initFromHandshakePacket:self];
}

- (CommitPacket*)parsedAsCommitPacket {
    return [[CommitPacket alloc] initFromHandshakePacket:self];
}

- (DHPacket*)parsedAsDH1 {
    return [[DHPacket alloc] initFromHandshakePacket:self andIsPartOne:true];
}

- (DHPacket*)parsedAsDH2 {
    return [[DHPacket alloc] initFromHandshakePacket:self andIsPartOne:false];
}

- (ConfirmPacket*)parsedAsConfirm1AuthenticatedWithMacKey:(NSData*)macKey andCipherKey:(NSData*)cipherKey {
    return [ConfirmPacket packetParsedFromHandshakePacket:self
                                               withMacKey:macKey
                                             andCipherKey:cipherKey
                                             andIsPartOne:true];
}

- (ConfirmPacket*)parsedAsConfirm2AuthenticatedWithMacKey:(NSData*)macKey andCipherKey:(NSData*)cipherKey {
    return [ConfirmPacket packetParsedFromHandshakePacket:self
                                               withMacKey:macKey
                                             andCipherKey:cipherKey
                                             andIsPartOne:false];
}

- (ConfirmAckPacket*)parsedAsConfAck {
    return [[ConfirmAckPacket alloc] initFromHandshakePacket:self];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Handshake: %@", [self.typeId decodedAsAsciiReplacingErrorsWithDots]];
}

@end
