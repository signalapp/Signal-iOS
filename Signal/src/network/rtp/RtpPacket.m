#import "RtpPacket.h"
#import "Util.h"
#import "Environment.h"

const uint8_t PACKET_VERSION = 2;
#define HAS_EXTENSION_HEADER_BIT_INDEX 4
#define HAS_PADDING_BIT_INDEX 5
#define VERSION_INDEX 6
#define MARKER_BIT_INDEX 7
#define EXTENSION_HEADER_IDENTIFIER_LENGTH 2
#define EXTENSION_HEADER_LENGTH_LENGTH 2
#define MINIMUM_RTP_HEADER_LENGTH 12

#define SEQUENCE_NUMBER_OFFSET 2
#define TIME_STAMP_OFFSET 4
#define SYNCHRONIZATION_SOURCE_IDENTIFIER_OFFSET 8
#define CONTRIBUTING_SOURCE_ID_LENGTH 4

#define VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET 0
#define PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET 1

#define SUPPORTED_RTP_VERSION 2
#define RTP_VERSION_FOR_ZRTP 0

#define PAYLOAD_TYPE_MASK 0x7F
#define MAX_EXTENSION_HEADER_LENGTH (0x10000 - 0x1)


@implementation RtpPacket

@synthesize payload;
@synthesize contributingSourceIdentifiers;
@synthesize hasExtensionHeader;
@synthesize isMarkerBitSet;
@synthesize padding;
@synthesize payloadType;
@synthesize sequenceNumber;
@synthesize synchronizationSourceIdentifier;
@synthesize timeStamp;
@synthesize version;
@synthesize wasAdjustedDueToInteropIssues;

+(RtpPacket*) rtpPacketWithDefaultsAndSequenceNumber:(uint16_t)sequenceNumber andPayload:(NSData *)payload {
    ows_require(payload != nil);
    return [RtpPacket rtpPacketWithVersion:PACKET_VERSION
                                andPadding:0
          andContributingSourceIdentifiers:@[]
        andSynchronizationSourceIdentifier:0
                              andMarkerBit:false
                            andPayloadtype:0
                         andSequenceNumber:sequenceNumber
                              andTimeStamp:0
                                andPayload:payload];
}
+(RtpPacket*) rtpPacketWithVersion:(uint8_t)version
                        andPadding:(uint8_t)padding
  andContributingSourceIdentifiers:(NSArray*)contributingSourceIdentifiers
andSynchronizationSourceIdentifier:(uint32_t)synchronizedSourceIdentifier
            andExtensionIdentifier:(uint16_t)extensionHeaderIdentifier
                  andExtensionData:(NSData*)extensionData
                      andMarkerBit:(bool)isMarkerBitSet
                    andPayloadtype:(uint8_t)payloadType
                 andSequenceNumber:(uint16_t)sequenceNumber
                      andTimeStamp:(uint32_t)timeStamp
                        andPayload:(NSData*)payload {
    
    ows_require((version & ~0x3) == 0);
    ows_require((payloadType & ~0x7F) == 0);
    ows_require(extensionData != nil);
    ows_require(extensionData.length < 0x10000);
    ows_require(contributingSourceIdentifiers != nil);
    ows_require(contributingSourceIdentifiers.count < 0x10);
    ows_require(payload != nil);
    
    RtpPacket* p = [RtpPacket new];
    p->version = version;
    p->isMarkerBitSet = isMarkerBitSet;
    p->hasExtensionHeader = true;
    p->extensionHeaderIdentifier = extensionHeaderIdentifier;
    p->extensionHeaderData = extensionData;
    p->padding = padding;
    p->contributingSourceIdentifiers = contributingSourceIdentifiers;
    p->payloadType = payloadType;
    p->synchronizationSourceIdentifier = synchronizedSourceIdentifier;
    p->timeStamp = timeStamp;
    p->sequenceNumber = sequenceNumber;
    p->payload = payload;
    return p;
}
+(RtpPacket*) rtpPacketWithVersion:(uint8_t)version
                        andPadding:(uint8_t)padding
  andContributingSourceIdentifiers:(NSArray*)contributingSourceIdentifiers
andSynchronizationSourceIdentifier:(uint32_t)synchronizedSourceIdentifier
                      andMarkerBit:(bool)isMarkerBitSet
                    andPayloadtype:(uint8_t)payloadType
                 andSequenceNumber:(uint16_t)sequenceNumber
                      andTimeStamp:(uint32_t)timeStamp
                        andPayload:(NSData*)payload {
    
    ows_require((version & ~0x3) == 0);
    ows_require((payloadType & ~0x7F) == 0);
    ows_require(contributingSourceIdentifiers != nil);
    ows_require(contributingSourceIdentifiers.count < 0x10);
    ows_require(payload != nil);
    
    RtpPacket* p = [RtpPacket new];
    p->version = version;
    p->isMarkerBitSet = isMarkerBitSet;
    p->padding = padding;
    p->contributingSourceIdentifiers = contributingSourceIdentifiers;
    p->payloadType = payloadType;
    p->synchronizationSourceIdentifier = synchronizedSourceIdentifier;
    p->timeStamp = timeStamp;
    p->sequenceNumber = sequenceNumber;
    p->payload = payload;
    return p;
}
-(RtpPacket*) withPayload:(NSData*)newPayload {
    if (hasExtensionHeader) {
        return [RtpPacket rtpPacketWithVersion:version
                                    andPadding:padding
              andContributingSourceIdentifiers:contributingSourceIdentifiers
            andSynchronizationSourceIdentifier:synchronizationSourceIdentifier
                        andExtensionIdentifier:extensionHeaderIdentifier
                              andExtensionData:extensionHeaderData
                                  andMarkerBit:isMarkerBitSet
                                andPayloadtype:payloadType
                             andSequenceNumber:sequenceNumber
                                  andTimeStamp:timeStamp
                                    andPayload:newPayload];
    }
    
    return [RtpPacket rtpPacketWithVersion:version
                                andPadding:padding
          andContributingSourceIdentifiers:contributingSourceIdentifiers
        andSynchronizationSourceIdentifier:synchronizationSourceIdentifier
                              andMarkerBit:isMarkerBitSet
                            andPayloadtype:payloadType
                         andSequenceNumber:sequenceNumber
                              andTimeStamp:timeStamp
                                andPayload:newPayload];
}

+(uint16_t) getSequenceNumberFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt16At:SEQUENCE_NUMBER_OFFSET];
}
+(uint32_t) getTimeStampFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt32At:TIME_STAMP_OFFSET];
}
+(uint32_t) getSynchronizationSourceIdentifierFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt32At:SYNCHRONIZATION_SOURCE_IDENTIFIER_OFFSET];
}
-(void) readContributingSourcesFromPacketData:(NSData*)packetData trackingOffset:(NSUInteger*)offset andMinSize:(NSUInteger*)minSize {
    uint8_t contributingSourceCount = [NumberUtil lowUInt4OfUint8:[packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET]];
    
    *minSize += contributingSourceCount * CONTRIBUTING_SOURCE_ID_LENGTH;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before header finished.");

    NSMutableArray* contributingSources = [NSMutableArray array];
    for (NSUInteger i = 0; i < contributingSourceCount; i++) {
        uint32_t ccsrc = [packetData bigEndianUInt32At:*offset];
        [contributingSources addObject:@(ccsrc)];
        *offset += CONTRIBUTING_SOURCE_ID_LENGTH;
    }
    
    contributingSourceIdentifiers = contributingSources;
}
-(void) readExtensionHeaderFromPacketData:(NSData*)packetData trackingOffset:(NSUInteger*)offset andMinSize:(NSUInteger*)minSize {
    hasExtensionHeader = (([packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET] >> HAS_EXTENSION_HEADER_BIT_INDEX) & 1) != 0;

    // legacy compatibility with android redphone
    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
        bool hasPadding = (([packetData uint8At:0] >> HAS_PADDING_BIT_INDEX) & 1) != 0;
        if (hasPadding) {
            wasAdjustedDueToInteropIssues = true;
            *offset += 12;
            hasExtensionHeader = true;
        }
    }
    
    if (!hasExtensionHeader) return;
    
    *minSize += EXTENSION_HEADER_IDENTIFIER_LENGTH + EXTENSION_HEADER_LENGTH_LENGTH;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before header of extension header finished.");

    extensionHeaderIdentifier = [packetData bigEndianUInt16At:*offset];
    *offset += EXTENSION_HEADER_IDENTIFIER_LENGTH;
    
    uint16_t extensionLength = [packetData bigEndianUInt16At:*offset];
    *offset += EXTENSION_HEADER_LENGTH_LENGTH;
    
    *minSize += extensionLength;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before payload of extension header finished.");
    
    extensionHeaderData = [packetData subdataWithRange:NSMakeRange(*offset, extensionLength)];
    *offset += extensionLength;
}
-(void) readPaddingFromPacketData:(NSData*)packetData andMinSize:(NSUInteger*)minSize {
    bool hasPadding = (([packetData uint8At:0] >> HAS_PADDING_BIT_INDEX) & 1) != 0;

    // legacy compatibility with android redphone
    if (hasPadding) {
        if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
            wasAdjustedDueToInteropIssues = true;
            hasPadding = false;
        }
    }
    
    if (!hasPadding) return;
    
    padding = [packetData uint8At:packetData.length - 1];
    checkOperationDescribe(padding > 0, @"Padding length must be at least 1 because it includes the suffix byte specifying the length.");
    
    *minSize += padding;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet overlaps header and padding.");
}
+(RtpPacket*) rtpPacketParsedFromPacketData:(NSData*)packetData {
    ows_require(packetData != nil);
    
    NSUInteger minSize = MINIMUM_RTP_HEADER_LENGTH;
    checkOperationDescribe(packetData.length >= minSize, @"Rtp packet ends before header finished.");
    
    RtpPacket* p = [RtpPacket new];
    
    p->rawPacketData = packetData;
    p->version = [packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET] >> VERSION_INDEX;
    checkOperation(p->version == SUPPORTED_RTP_VERSION || p->version == RTP_VERSION_FOR_ZRTP);
    
    p->isMarkerBitSet = (([packetData uint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET] >> MARKER_BIT_INDEX) & 1) != 0;;
    p->payloadType = [packetData uint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET] & PAYLOAD_TYPE_MASK;

    NSUInteger offset = MINIMUM_RTP_HEADER_LENGTH;
    [p readContributingSourcesFromPacketData:packetData trackingOffset:&offset andMinSize:&minSize];
    [p readExtensionHeaderFromPacketData:packetData trackingOffset:&offset andMinSize:&minSize];
    [p readPaddingFromPacketData:packetData andMinSize:&minSize];
    p->payload = [packetData subdataWithRange:NSMakeRange(offset, packetData.length - p->padding - offset)];
    
    p->sequenceNumber = [self getSequenceNumberFromPacketData:packetData];
    p->timeStamp = [self getTimeStampFromPacketData:packetData];
    p->synchronizationSourceIdentifier = [self getSynchronizationSourceIdentifierFromPacketData:packetData];
    
    return p;
}

-(NSData*) generateFlags {
    requireState((version & ~0x3) == 0);
    requireState((payloadType & ~0x7F) == 0);
    requireState(contributingSourceIdentifiers.count < 0x10);
    
    NSMutableData* flags = [NSMutableData dataWithLength:2];
    
    uint8_t versionMask = (uint8_t)(version << VERSION_INDEX);
    uint8_t paddingBit = padding > 0 ? (uint8_t)(1<<HAS_PADDING_BIT_INDEX) : 0;
    uint8_t extensionBit = hasExtensionHeader ? (uint8_t)(1<<HAS_EXTENSION_HEADER_BIT_INDEX) : 0;
    uint8_t ccsrcCount = (uint8_t)contributingSourceIdentifiers.count;
    [flags setUint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET
                   to:versionMask | paddingBit | extensionBit | ccsrcCount];
    
    uint8_t markerMask = isMarkerBitSet ? (uint8_t)(1 << MARKER_BIT_INDEX) : 0;
    [flags setUint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET
                   to:markerMask | payloadType];
    
    return flags;
}
-(NSData*) generateCcrcData {
    return [[contributingSourceIdentifiers map:^id(NSNumber* ccsrc) {
        return [NSData dataWithBigEndianBytesOfUInt32:[ccsrc unsignedIntValue]];
    }] ows_concatDatas];
}
-(NSData*) generateExtensionHeaderData {
    if (!hasExtensionHeader) return [NSData data];
    
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:extensionHeaderIdentifier],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)extensionHeaderData.length],
            extensionHeaderData
            ] ows_concatDatas];
}
-(NSData*) generatePaddingData {
    NSMutableData* paddingData = [NSMutableData dataWithLength:padding];
    if (padding > 0) {
        [paddingData setUint8At:paddingData.length - 1 to:padding];
    }
    return paddingData;
}
-(NSData*) generateSerializedPacketDataUsingInteropOptions:(NSArray*)interopOptions {
    requireState(hasExtensionHeader == (extensionHeaderData != nil));
    requireState(extensionHeaderData == nil || extensionHeaderData.length <= MAX_EXTENSION_HEADER_LENGTH);
    
    NSData* shouldBeEmpty = [NSData data];
    
    // legacy compatibility with android redphone
    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
        if ([interopOptions containsObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
            if (hasExtensionHeader) {
                shouldBeEmpty = [NSData dataWithLength:12];
            }
        }
    }
    
    return [@[
            [self generateFlags],
            [NSData dataWithBigEndianBytesOfUInt16:sequenceNumber],
            [NSData dataWithBigEndianBytesOfUInt32:timeStamp],
            [NSData dataWithBigEndianBytesOfUInt32:synchronizationSourceIdentifier],
            [self generateCcrcData],
            shouldBeEmpty,
            [self generateExtensionHeaderData],
            payload,
            [self generatePaddingData]
            ] ows_concatDatas];
}

-(RtpPacket*) withSequenceNumber:(uint16_t)newSequenceNumber {
    RtpPacket* p = [RtpPacket new];
    p->version = version;
    p->padding = padding;
    p->hasExtensionHeader = hasExtensionHeader;
    p->contributingSourceIdentifiers = contributingSourceIdentifiers;
    p->isMarkerBitSet = isMarkerBitSet;
    p->payloadType = payloadType;
    p->timeStamp = timeStamp;
    p->synchronizationSourceIdentifier = synchronizationSourceIdentifier;
    p->extensionHeaderIdentifier = extensionHeaderIdentifier;
    p->extensionHeaderData = extensionHeaderData;
    p->payload = payload;
    
    p->sequenceNumber = newSequenceNumber;
    return p;
}

-(uint16_t) extensionHeaderIdentifier {
    requireState(hasExtensionHeader);
    return extensionHeaderIdentifier;
}
-(NSData*) extensionHeaderData {
    requireState(hasExtensionHeader);
    return extensionHeaderData;
}
-(NSData*) rawPacketDataUsingInteropOptions:(NSArray*)interopOptions {
    if (rawPacketData == nil) rawPacketData = [self generateSerializedPacketDataUsingInteropOptions:interopOptions];
    return rawPacketData;
}
-(bool) isEqualToRtpPacket:(RtpPacket*)other {
    if (other == nil) return false;
    if (version != [other version]) return false;
    if (padding != [other padding]) return false;
    if (hasExtensionHeader != other.hasExtensionHeader) return false;
    if (isMarkerBitSet != other.isMarkerBitSet) return false;
    if (payloadType != [other payloadType]) return false;
    if (timeStamp != [other timeStamp]) return false;
    if (synchronizationSourceIdentifier != [other synchronizationSourceIdentifier]) return false;
    if (sequenceNumber != [other sequenceNumber]) return false;
    
    if (![payload isEqualToData:[other payload]]) return false;
    if (![contributingSourceIdentifiers isEqualToArray:[other contributingSourceIdentifiers]]) return false;
    if (hasExtensionHeader) {
        if (extensionHeaderIdentifier != [other extensionHeaderIdentifier]) return false;
        if (![extensionHeaderData isEqualToData:[other extensionHeaderData]]) return false;
    }
    
    if (![[self rawPacketDataUsingInteropOptions:@[]] isEqualToData:[other rawPacketDataUsingInteropOptions:@[]]]) return false;
    
    return true;
}

@end
