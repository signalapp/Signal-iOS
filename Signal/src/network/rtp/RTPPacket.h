#import <Foundation/Foundation.h>
#import "NSData+Conversions.h"

/**
 *
 * A Real Time Protocol packet (see RFC 3550, RFC 1889)
 *
**/

@interface RTPPacket : NSObject

@property (readonly, nonatomic) uint8_t version;
@property (readonly, nonatomic) uint8_t padding;
@property (readonly, nonatomic) uint8_t payloadType;
@property (readonly, nonatomic) uint16_t sequenceNumber;
@property (readonly, nonatomic) uint16_t extensionHeaderIdentifier;
@property (readonly, nonatomic) uint32_t timeStamp;
@property (readonly, nonatomic) uint32_t synchronizationSourceIdentifier;
@property (readonly, nonatomic) bool isMarkerBitSet;
@property (readonly, nonatomic) bool hasExtensionHeader;
@property (readonly, nonatomic) bool wasAdjustedDueToInteropIssues;
@property (strong, readonly, nonatomic) NSArray* contributingSourceIdentifiers;
@property (strong, readonly, nonatomic) NSData* extensionHeaderData;
@property (strong, readonly, nonatomic) NSData* payload;

- (instancetype)initWithDefaultsAndSequenceNumber:(uint16_t)sequenceNumber
                                       andPayload:(NSData*)payload;

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
                     andPayload:(NSData*)payload;

- (instancetype)initWithVersion:(uint8_t)version
                     andPadding:(uint8_t)padding
andContributingSourceIdentifiers:(NSArray*)contributingSourceIdentifiers
andSynchronizationSourceIdentifier:(uint32_t)synchronizedSourceIdentifier
                   andMarkerBit:(bool)isMarkerBitSet
                 andPayloadtype:(uint8_t)payloadType
              andSequenceNumber:(uint16_t)sequenceNumber
                   andTimeStamp:(uint32_t)timeStamp
                     andPayload:(NSData*)payload;

- (instancetype)initFromPacketData:(NSData*)packetData;

- (RTPPacket*)withPayload:(NSData*)newPayload;
- (RTPPacket*)withSequenceNumber:(uint16_t)newSequenceNumber;

- (NSData*)rawPacketDataUsingInteropOptions:(NSArray*)interopOptions;

- (bool)isEqualToRTPPacket:(RTPPacket*)other;

@end
