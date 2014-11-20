#import "RTPPacket.h"
#import "Util.h"
#import "Constraints.h"
#import "NSArray+FunctionalUtil.h"
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


@interface RTPPacket ()

@property (readwrite, nonatomic) uint8_t version;
@property (readwrite, nonatomic) uint8_t padding;
@property (readwrite, nonatomic) uint8_t payloadType;
@property (readwrite, nonatomic) uint16_t sequenceNumber;
@property (readwrite, nonatomic) uint16_t extensionHeaderIdentifier;
@property (readwrite, nonatomic) uint32_t timeStamp;
@property (readwrite, nonatomic) uint32_t synchronizationSourceIdentifier;
@property (readwrite, nonatomic) bool isMarkerBitSet;
@property (readwrite, nonatomic) bool hasExtensionHeader;
@property (readwrite, nonatomic) bool wasAdjustedDueToInteropIssues;
@property (strong, readwrite, nonatomic) NSArray* contributingSourceIdentifiers;
@property (strong, readwrite, nonatomic) NSData* extensionHeaderData;
@property (strong, readwrite, nonatomic) NSData* payload;
@property (strong, nonatomic) NSData* rawPacketData;

@end

@implementation RTPPacket

- (instancetype)initWithDefaultsAndSequenceNumber:(uint16_t)sequenceNumber
                                       andPayload:(NSData*)payload {
    require(payload != nil);
    return [[RTPPacket alloc] initWithVersion:PACKET_VERSION
                                   andPadding:0
             andContributingSourceIdentifiers:@[]
           andSynchronizationSourceIdentifier:0
                                 andMarkerBit:false
                               andPayloadtype:0
                            andSequenceNumber:sequenceNumber
                                 andTimeStamp:0
                                   andPayload:payload];
}

- (instancetype)initWithVersion:(uint8_t)version
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
    self = [super init];
	
    if (self) {
        require((version & ~0x3) == 0);
        require((payloadType & ~0x7F) == 0);
        require(contributingSourceIdentifiers != nil);
        require(contributingSourceIdentifiers.count < 0x10);
        require(payload != nil);
        
        if (extensionData) {
            require(extensionData.length < 0x10000);
            self.hasExtensionHeader          = true;
            self.extensionHeaderIdentifier   = extensionHeaderIdentifier;
            self.extensionHeaderData         = extensionData;
        } else {
            self.hasExtensionHeader          = false;
        }
        
        self.version                         = version;
        self.isMarkerBitSet                  = isMarkerBitSet;
        self.padding                         = padding;
        self.contributingSourceIdentifiers   = contributingSourceIdentifiers;
        self.payloadType                     = payloadType;
        self.synchronizationSourceIdentifier = synchronizedSourceIdentifier;
        self.timeStamp                       = timeStamp;
        self.sequenceNumber                  = sequenceNumber;
        self.payload                         = payload;
    }
    
    return self;
}

- (instancetype)initWithVersion:(uint8_t)version
                     andPadding:(uint8_t)padding
andContributingSourceIdentifiers:(NSArray*)contributingSourceIdentifiers
andSynchronizationSourceIdentifier:(uint32_t)synchronizedSourceIdentifier
                   andMarkerBit:(bool)isMarkerBitSet
                 andPayloadtype:(uint8_t)payloadType
              andSequenceNumber:(uint16_t)sequenceNumber
                   andTimeStamp:(uint32_t)timeStamp
                     andPayload:(NSData*)payload {
    return [self initWithVersion:version
                      andPadding:padding
andContributingSourceIdentifiers:contributingSourceIdentifiers
andSynchronizationSourceIdentifier:synchronizedSourceIdentifier
          andExtensionIdentifier:0
                andExtensionData:nil
                    andMarkerBit:isMarkerBitSet
                  andPayloadtype:payloadType
               andSequenceNumber:sequenceNumber
                    andTimeStamp:timeStamp
                      andPayload:payload];
}

- (instancetype)initFromPacketData:(NSData*)packetData {
    self = [super init];
	
    if (self) {
        require(packetData != nil);
        
        NSUInteger minSize = MINIMUM_RTP_HEADER_LENGTH;
        checkOperationDescribe(packetData.length >= minSize, @"Rtp packet ends before header finished.");
        
        self.rawPacketData = packetData;
        self.version = [packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET] >> VERSION_INDEX;
        checkOperation(self.version == SUPPORTED_RTP_VERSION || self.version == RTP_VERSION_FOR_ZRTP);
        
        self.isMarkerBitSet = (([packetData uint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET] >> MARKER_BIT_INDEX) & 1) != 0;;
        self.payloadType = [packetData uint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET] & PAYLOAD_TYPE_MASK;
        
        NSUInteger offset = MINIMUM_RTP_HEADER_LENGTH;
        [self readContributingSourcesFromPacketData:packetData trackingOffset:&offset andMinSize:&minSize];
        [self readExtensionHeaderFromPacketData:packetData trackingOffset:&offset andMinSize:&minSize];
        [self readPaddingFromPacketData:packetData andMinSize:&minSize];
        self.payload = [packetData subdataWithRange:NSMakeRange(offset, packetData.length - self.padding - offset)];
        
        self.sequenceNumber = [RTPPacket getSequenceNumberFromPacketData:packetData];
        self.timeStamp = [RTPPacket getTimeStampFromPacketData:packetData];
        self.synchronizationSourceIdentifier = [RTPPacket getSynchronizationSourceIdentifierFromPacketData:packetData];
    }
    
    return self;
}

- (RTPPacket*)withPayload:(NSData*)newPayload {
    return [[RTPPacket alloc] initWithVersion:self.version
                                   andPadding:self.padding
             andContributingSourceIdentifiers:self.contributingSourceIdentifiers
           andSynchronizationSourceIdentifier:self.synchronizationSourceIdentifier
                       andExtensionIdentifier:self.extensionHeaderIdentifier
                             andExtensionData:self.extensionHeaderData
                                 andMarkerBit:self.isMarkerBitSet
                               andPayloadtype:self.payloadType
                            andSequenceNumber:self.sequenceNumber
                                 andTimeStamp:self.timeStamp
                                   andPayload:newPayload];
}

- (RTPPacket*)withSequenceNumber:(uint16_t)newSequenceNumber {
    return [[RTPPacket alloc] initWithVersion:self.version
                                   andPadding:self.padding
             andContributingSourceIdentifiers:self.contributingSourceIdentifiers
           andSynchronizationSourceIdentifier:self.synchronizationSourceIdentifier
                       andExtensionIdentifier:self.extensionHeaderIdentifier
                             andExtensionData:self.extensionHeaderData
                                 andMarkerBit:self.isMarkerBitSet
                               andPayloadtype:self.payloadType
                            andSequenceNumber:newSequenceNumber
                                 andTimeStamp:self.timeStamp
                                   andPayload:self.payload];
}

+ (uint16_t)getSequenceNumberFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt16At:SEQUENCE_NUMBER_OFFSET];
}

+ (uint32_t)getTimeStampFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt32At:TIME_STAMP_OFFSET];
}

+ (uint32_t)getSynchronizationSourceIdentifierFromPacketData:(NSData*)packetData {
    return [packetData bigEndianUInt32At:SYNCHRONIZATION_SOURCE_IDENTIFIER_OFFSET];
}

- (void)readContributingSourcesFromPacketData:(NSData*)packetData
                               trackingOffset:(NSUInteger*)offset
                                   andMinSize:(NSUInteger*)minSize {
    
    uint8_t contributingSourceCount = [NumberUtil lowUInt4OfUint8:[packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET]];
    
    *minSize += contributingSourceCount * CONTRIBUTING_SOURCE_ID_LENGTH;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before header finished.");

    NSMutableArray* contributingSources = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < contributingSourceCount; i++) {
        uint32_t ccsrc = [packetData bigEndianUInt32At:*offset];
        [contributingSources addObject:@(ccsrc)];
        *offset += CONTRIBUTING_SOURCE_ID_LENGTH;
    }
    
    self.contributingSourceIdentifiers = contributingSources;
}

- (void)readExtensionHeaderFromPacketData:(NSData*)packetData
                           trackingOffset:(NSUInteger*)offset
                               andMinSize:(NSUInteger*)minSize {
    
    self.hasExtensionHeader = (([packetData uint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET] >>
                                HAS_EXTENSION_HEADER_BIT_INDEX) & 1) != 0;

    // legacy compatibility with android redphone
    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
        bool hasPadding = (([packetData uint8At:0] >> HAS_PADDING_BIT_INDEX) & 1) != 0;
        if (hasPadding) {
            self.wasAdjustedDueToInteropIssues = true;
            *offset += 12;
            self.hasExtensionHeader = true;
        }
    }
    
    if (!self.hasExtensionHeader) return;
    
    *minSize += EXTENSION_HEADER_IDENTIFIER_LENGTH + EXTENSION_HEADER_LENGTH_LENGTH;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before header of extension header finished.");

    self.extensionHeaderIdentifier = [packetData bigEndianUInt16At:*offset];
    *offset += EXTENSION_HEADER_IDENTIFIER_LENGTH;
    
    uint16_t extensionLength = [packetData bigEndianUInt16At:*offset];
    *offset += EXTENSION_HEADER_LENGTH_LENGTH;
    
    *minSize += extensionLength;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet ends before payload of extension header finished.");
    
    self.extensionHeaderData = [packetData subdataWithRange:NSMakeRange(*offset, extensionLength)];
    *offset += extensionLength;
}

- (void)readPaddingFromPacketData:(NSData*)packetData
                       andMinSize:(NSUInteger*)minSize {
    bool hasPadding = (([packetData uint8At:0] >> HAS_PADDING_BIT_INDEX) & 1) != 0;

    // legacy compatibility with android redphone
    if (hasPadding) {
        if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
            self.wasAdjustedDueToInteropIssues = true;
            hasPadding = false;
        }
    }
    
    if (!hasPadding) return;
    
    self.padding = [packetData uint8At:packetData.length - 1];
    checkOperationDescribe(self.padding > 0, @"Padding length must be at least 1 because it includes the suffix byte specifying the length.");
    
    *minSize += self.padding;
    checkOperationDescribe(packetData.length >= *minSize, @"Rtp packet overlaps header and padding.");
}

- (NSData*)generateFlags {
    requireState((self.version & ~0x3) == 0);
    requireState((self.payloadType & ~0x7F) == 0);
    requireState(self.contributingSourceIdentifiers.count < 0x10);
    
    NSMutableData* flags = [NSMutableData dataWithLength:2];
    
    uint8_t versionMask = (uint8_t)(self.version << VERSION_INDEX);
    uint8_t paddingBit = self.padding > 0 ? (uint8_t)(1<<HAS_PADDING_BIT_INDEX) : 0;
    uint8_t extensionBit = self.hasExtensionHeader ? (uint8_t)(1<<HAS_EXTENSION_HEADER_BIT_INDEX) : 0;
    uint8_t ccsrcCount = (uint8_t)self.contributingSourceIdentifiers.count;
    [flags setUint8At:VERSION_AND_PADDING_AND_EXTENSION_AND_CCSRC_FLAG_BYTE_OFFSET
                   to:versionMask | paddingBit | extensionBit | ccsrcCount];
    
    uint8_t markerMask = self.isMarkerBitSet ? (uint8_t)(1 << MARKER_BIT_INDEX) : 0;
    [flags setUint8At:PAYLOAD_TYPE_AND_MARKER_BIT_FLAG_BYTE_OFFSET
                   to:markerMask | self.payloadType];
    
    return flags;
}

- (NSData*)generateCcrcData {
    return [[self.contributingSourceIdentifiers map:^id(NSNumber* ccsrc) {
        return [NSData dataWithBigEndianBytesOfUInt32:[ccsrc unsignedIntValue]];
    }] concatDatas];
}

- (NSData*)generateExtensionHeaderData {
    if (!self.hasExtensionHeader) return [[NSData alloc] init];
    
    return [@[
            [NSData dataWithBigEndianBytesOfUInt16:self.extensionHeaderIdentifier],
            [NSData dataWithBigEndianBytesOfUInt16:(uint16_t)self.extensionHeaderData.length],
            self.extensionHeaderData
            ] concatDatas];
}

- (NSData*)generatePaddingData {
    NSMutableData* paddingData = [NSMutableData dataWithLength:self.padding];
    if (self.padding > 0) {
        [paddingData setUint8At:paddingData.length - 1 to:self.padding];
    }
    return paddingData;
}

- (NSData*)generateSerializedPacketDataUsingInteropOptions:(NSArray*)interopOptions {
    requireState(self.hasExtensionHeader == (self.extensionHeaderData != nil));
    requireState(self.extensionHeaderData == nil || self.extensionHeaderData.length <= MAX_EXTENSION_HEADER_LENGTH);
    
    NSData* shouldBeEmpty = [[NSData alloc] init];
    
    // legacy compatibility with android redphone
    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
        if ([interopOptions containsObject:ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER]) {
            if (self.hasExtensionHeader) {
                shouldBeEmpty = [NSData dataWithLength:12];
            }
        }
    }
    
    return [@[
            [self generateFlags],
            [NSData dataWithBigEndianBytesOfUInt16:self.sequenceNumber],
            [NSData dataWithBigEndianBytesOfUInt32:self.timeStamp],
            [NSData dataWithBigEndianBytesOfUInt32:self.synchronizationSourceIdentifier],
            [self generateCcrcData],
            shouldBeEmpty,
            [self generateExtensionHeaderData],
            self.payload,
            [self generatePaddingData]
            ] concatDatas];
}

- (NSData*)rawPacketDataUsingInteropOptions:(NSArray*)interopOptions {
    if (!self.rawPacketData) {
        self.rawPacketData = [self generateSerializedPacketDataUsingInteropOptions:interopOptions];
    }
    return self.rawPacketData;
}

- (bool)isEqualToRTPPacket:(RTPPacket*)other {
    if (other                                == nil)                                   return false;
    if (self.version                         != other.version)                         return false;
    if (self.padding                         != other.padding)                         return false;
    if (self.hasExtensionHeader              != other.hasExtensionHeader)              return false;
    if (self.isMarkerBitSet                  != other.isMarkerBitSet)                  return false;
    if (self.payloadType                     != other.payloadType)                     return false;
    if (self.timeStamp                       != other.timeStamp)                       return false;
    if (self.synchronizationSourceIdentifier != other.synchronizationSourceIdentifier) return false;
    if (self.sequenceNumber                  != other.sequenceNumber)                  return false;
    
    if (![self.payload isEqualToData:other.payload])                                   return false;
    
    if (![self.contributingSourceIdentifiers isEqualToArray:other.contributingSourceIdentifiers]) return false;
    if (self.hasExtensionHeader) {
        if (self.extensionHeaderIdentifier != other.extensionHeaderIdentifier) return false;
        if (![self.extensionHeaderData isEqualToData:other.extensionHeaderData]) return false;
    }
    
    if (![[self rawPacketDataUsingInteropOptions:@[]] isEqualToData:[other rawPacketDataUsingInteropOptions:@[]]]) return false;
    
    return true;
}

@end
