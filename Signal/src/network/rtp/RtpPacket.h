#import <Foundation/Foundation.h>
#import "Conversions.h"

/**
 *
 * A Real Time Protocol packet (see RFC 3550, RFC 1889)
 *
**/

@interface RtpPacket : NSObject {
@private uint16_t extensionHeaderIdentifier;
@private NSData* extensionHeaderData;
@private NSData* rawPacketData;
}

@property (nonatomic,readonly) bool wasAdjustedDueToInteropIssues;

@property (nonatomic,readonly) uint8_t version;
@property (nonatomic,readonly) uint8_t padding;
@property (nonatomic,readonly) bool hasExtensionHeader;
@property (nonatomic,readonly) NSArray* contributingSourceIdentifiers;
@property (nonatomic,readonly) bool isMarkerBitSet;
@property (nonatomic,readonly) uint8_t payloadType;
@property (nonatomic,readonly) uint16_t sequenceNumber;
@property (nonatomic,readonly) uint32_t timeStamp;
@property (nonatomic,readonly) uint32_t synchronizationSourceIdentifier;
@property (nonatomic,readonly) NSData* payload;

+(RtpPacket*) rtpPacketWithDefaultsAndSequenceNumber:(uint16_t)sequenceNumber andPayload:(NSData*)payload;

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
                        andPayload:(NSData*)payload;

+(RtpPacket*) rtpPacketWithVersion:(uint8_t)version
                        andPadding:(uint8_t)padding
  andContributingSourceIdentifiers:(NSArray*)contributingSourceIdentifiers
andSynchronizationSourceIdentifier:(uint32_t)synchronizedSourceIdentifier
                      andMarkerBit:(bool)isMarkerBitSet
                    andPayloadtype:(uint8_t)payloadType
                 andSequenceNumber:(uint16_t)sequenceNumber
                      andTimeStamp:(uint32_t)timeStamp
                        andPayload:(NSData*)payload;

+(RtpPacket*) rtpPacketParsedFromPacketData:(NSData*)packetData;

-(RtpPacket*) withPayload:(NSData*)newPayload;
-(RtpPacket*) withSequenceNumber:(uint16_t)newSequenceNumber;

-(uint16_t) extensionHeaderIdentifier;
-(NSData*) extensionHeaderData;
-(NSData*) rawPacketDataUsingInteropOptions:(NSArray*)interopOptions;

-(bool) isEqualToRtpPacket:(RtpPacket*)other;

@end
