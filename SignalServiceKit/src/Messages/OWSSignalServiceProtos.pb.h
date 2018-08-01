//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <ProtocolBuffers/ProtocolBuffers.h>

// @@protoc_insertion_point(imports)

@class ObjectiveCFileOptions;
@class ObjectiveCFileOptionsBuilder;
@class PBDescriptorProto;
@class PBDescriptorProtoBuilder;
@class PBDescriptorProtoExtensionRange;
@class PBDescriptorProtoExtensionRangeBuilder;
@class PBEnumDescriptorProto;
@class PBEnumDescriptorProtoBuilder;
@class PBEnumOptions;
@class PBEnumOptionsBuilder;
@class PBEnumValueDescriptorProto;
@class PBEnumValueDescriptorProtoBuilder;
@class PBEnumValueOptions;
@class PBEnumValueOptionsBuilder;
@class PBFieldDescriptorProto;
@class PBFieldDescriptorProtoBuilder;
@class PBFieldOptions;
@class PBFieldOptionsBuilder;
@class PBFileDescriptorProto;
@class PBFileDescriptorProtoBuilder;
@class PBFileDescriptorSet;
@class PBFileDescriptorSetBuilder;
@class PBFileOptions;
@class PBFileOptionsBuilder;
@class PBMessageOptions;
@class PBMessageOptionsBuilder;
@class PBMethodDescriptorProto;
@class PBMethodDescriptorProtoBuilder;
@class PBMethodOptions;
@class PBMethodOptionsBuilder;
@class PBOneofDescriptorProto;
@class PBOneofDescriptorProtoBuilder;
@class PBServiceDescriptorProto;
@class PBServiceDescriptorProtoBuilder;
@class PBServiceOptions;
@class PBServiceOptionsBuilder;
@class PBSourceCodeInfo;
@class PBSourceCodeInfoBuilder;
@class PBSourceCodeInfoLocation;
@class PBSourceCodeInfoLocationBuilder;
@class PBUninterpretedOption;
@class PBUninterpretedOptionBuilder;
@class PBUninterpretedOptionNamePart;
@class PBUninterpretedOptionNamePartBuilder;
@class SSKProtoAttachmentPointer;
@class SSKProtoAttachmentPointerBuilder;
@class SSKProtoCallMessage;
@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageAnswerBuilder;
@class SSKProtoCallMessageBuilder;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageBusyBuilder;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageHangupBuilder;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageIceUpdateBuilder;
@class SSKProtoCallMessageOffer;
@class SSKProtoCallMessageOfferBuilder;
@class SSKProtoContactDetails;
@class SSKProtoContactDetailsAvatar;
@class SSKProtoContactDetailsAvatarBuilder;
@class SSKProtoContactDetailsBuilder;
@class SSKProtoContent;
@class SSKProtoContentBuilder;
@class SSKProtoDataMessage;
@class SSKProtoDataMessageBuilder;
@class SSKProtoDataMessageContact;
@class SSKProtoDataMessageContactAvatar;
@class SSKProtoDataMessageContactAvatarBuilder;
@class SSKProtoDataMessageContactBuilder;
@class SSKProtoDataMessageContactEmail;
@class SSKProtoDataMessageContactEmailBuilder;
@class SSKProtoDataMessageContactName;
@class SSKProtoDataMessageContactNameBuilder;
@class SSKProtoDataMessageContactPhone;
@class SSKProtoDataMessageContactPhoneBuilder;
@class SSKProtoDataMessageContactPostalAddress;
@class SSKProtoDataMessageContactPostalAddressBuilder;
@class SSKProtoDataMessageQuote;
@class SSKProtoDataMessageQuoteBuilder;
@class SSKProtoDataMessageQuoteQuotedAttachment;
@class SSKProtoDataMessageQuoteQuotedAttachmentBuilder;
@class SSKProtoEnvelope;
@class SSKProtoEnvelopeBuilder;
@class SSKProtoGroupContext;
@class SSKProtoGroupContextBuilder;
@class SSKProtoGroupDetails;
@class SSKProtoGroupDetailsAvatar;
@class SSKProtoGroupDetailsAvatarBuilder;
@class SSKProtoGroupDetailsBuilder;
@class SSKProtoNullMessage;
@class SSKProtoNullMessageBuilder;
@class SSKProtoReceiptMessage;
@class SSKProtoReceiptMessageBuilder;
@class SSKProtoSyncMessage;
@class SSKProtoSyncMessageBlocked;
@class SSKProtoSyncMessageBlockedBuilder;
@class SSKProtoSyncMessageBuilder;
@class SSKProtoSyncMessageConfiguration;
@class SSKProtoSyncMessageConfigurationBuilder;
@class SSKProtoSyncMessageContacts;
@class SSKProtoSyncMessageContactsBuilder;
@class SSKProtoSyncMessageGroups;
@class SSKProtoSyncMessageGroupsBuilder;
@class SSKProtoSyncMessageRead;
@class SSKProtoSyncMessageReadBuilder;
@class SSKProtoSyncMessageRequest;
@class SSKProtoSyncMessageRequestBuilder;
@class SSKProtoSyncMessageSent;
@class SSKProtoSyncMessageSentBuilder;
@class SSKProtoVerified;
@class SSKProtoVerifiedBuilder;

typedef NS_ENUM(SInt32, SSKProtoEnvelopeType) {
  SSKProtoEnvelopeTypeUnknown = 0,
  SSKProtoEnvelopeTypeCiphertext = 1,
  SSKProtoEnvelopeTypeKeyExchange = 2,
  SSKProtoEnvelopeTypePrekeyBundle = 3,
  SSKProtoEnvelopeTypeReceipt = 5,
};

BOOL SSKProtoEnvelopeTypeIsValidValue(SSKProtoEnvelopeType value);
NSString *NSStringFromSSKProtoEnvelopeType(SSKProtoEnvelopeType value);

typedef NS_ENUM(SInt32, SSKProtoDataMessageFlags) {
  SSKProtoDataMessageFlagsEndSession = 1,
  SSKProtoDataMessageFlagsExpirationTimerUpdate = 2,
  SSKProtoDataMessageFlagsProfileKeyUpdate = 4,
};

BOOL SSKProtoDataMessageFlagsIsValidValue(SSKProtoDataMessageFlags value);
NSString *NSStringFromSSKProtoDataMessageFlags(SSKProtoDataMessageFlags value);

typedef NS_ENUM(SInt32, SSKProtoDataMessageQuoteQuotedAttachmentFlags) {
  SSKProtoDataMessageQuoteQuotedAttachmentFlagsVoiceMessage = 1,
};

BOOL SSKProtoDataMessageQuoteQuotedAttachmentFlagsIsValidValue(SSKProtoDataMessageQuoteQuotedAttachmentFlags value);
NSString *NSStringFromSSKProtoDataMessageQuoteQuotedAttachmentFlags(SSKProtoDataMessageQuoteQuotedAttachmentFlags value);

typedef NS_ENUM(SInt32, SSKProtoDataMessageContactPhoneType) {
  SSKProtoDataMessageContactPhoneTypeHome = 1,
  SSKProtoDataMessageContactPhoneTypeMobile = 2,
  SSKProtoDataMessageContactPhoneTypeWork = 3,
  SSKProtoDataMessageContactPhoneTypeCustom = 4,
};

BOOL SSKProtoDataMessageContactPhoneTypeIsValidValue(SSKProtoDataMessageContactPhoneType value);
NSString *NSStringFromSSKProtoDataMessageContactPhoneType(SSKProtoDataMessageContactPhoneType value);

typedef NS_ENUM(SInt32, SSKProtoDataMessageContactEmailType) {
  SSKProtoDataMessageContactEmailTypeHome = 1,
  SSKProtoDataMessageContactEmailTypeMobile = 2,
  SSKProtoDataMessageContactEmailTypeWork = 3,
  SSKProtoDataMessageContactEmailTypeCustom = 4,
};

BOOL SSKProtoDataMessageContactEmailTypeIsValidValue(SSKProtoDataMessageContactEmailType value);
NSString *NSStringFromSSKProtoDataMessageContactEmailType(SSKProtoDataMessageContactEmailType value);

typedef NS_ENUM(SInt32, SSKProtoDataMessageContactPostalAddressType) {
  SSKProtoDataMessageContactPostalAddressTypeHome = 1,
  SSKProtoDataMessageContactPostalAddressTypeWork = 2,
  SSKProtoDataMessageContactPostalAddressTypeCustom = 3,
};

BOOL SSKProtoDataMessageContactPostalAddressTypeIsValidValue(SSKProtoDataMessageContactPostalAddressType value);
NSString *NSStringFromSSKProtoDataMessageContactPostalAddressType(SSKProtoDataMessageContactPostalAddressType value);

typedef NS_ENUM(SInt32, SSKProtoReceiptMessageType) {
  SSKProtoReceiptMessageTypeDelivery = 0,
  SSKProtoReceiptMessageTypeRead = 1,
};

BOOL SSKProtoReceiptMessageTypeIsValidValue(SSKProtoReceiptMessageType value);
NSString *NSStringFromSSKProtoReceiptMessageType(SSKProtoReceiptMessageType value);

typedef NS_ENUM(SInt32, SSKProtoVerifiedState) {
  SSKProtoVerifiedStateDefault = 0,
  SSKProtoVerifiedStateVerified = 1,
  SSKProtoVerifiedStateUnverified = 2,
};

BOOL SSKProtoVerifiedStateIsValidValue(SSKProtoVerifiedState value);
NSString *NSStringFromSSKProtoVerifiedState(SSKProtoVerifiedState value);

typedef NS_ENUM(SInt32, SSKProtoSyncMessageRequestType) {
  SSKProtoSyncMessageRequestTypeUnknown = 0,
  SSKProtoSyncMessageRequestTypeContacts = 1,
  SSKProtoSyncMessageRequestTypeGroups = 2,
  SSKProtoSyncMessageRequestTypeBlocked = 3,
  SSKProtoSyncMessageRequestTypeConfiguration = 4,
};

BOOL SSKProtoSyncMessageRequestTypeIsValidValue(SSKProtoSyncMessageRequestType value);
NSString *NSStringFromSSKProtoSyncMessageRequestType(SSKProtoSyncMessageRequestType value);

typedef NS_ENUM(SInt32, SSKProtoAttachmentPointerFlags) {
  SSKProtoAttachmentPointerFlagsVoiceMessage = 1,
};

BOOL SSKProtoAttachmentPointerFlagsIsValidValue(SSKProtoAttachmentPointerFlags value);
NSString *NSStringFromSSKProtoAttachmentPointerFlags(SSKProtoAttachmentPointerFlags value);

typedef NS_ENUM(SInt32, SSKProtoGroupContextType) {
  SSKProtoGroupContextTypeUnknown = 0,
  SSKProtoGroupContextTypeUpdate = 1,
  SSKProtoGroupContextTypeDeliver = 2,
  SSKProtoGroupContextTypeQuit = 3,
  SSKProtoGroupContextTypeRequestInfo = 4,
};

BOOL SSKProtoGroupContextTypeIsValidValue(SSKProtoGroupContextType value);
NSString *NSStringFromSSKProtoGroupContextType(SSKProtoGroupContextType value);


@interface OWSSignalServiceProtosSSKProtoRoot : NSObject {
}
+ (PBExtensionRegistry*) extensionRegistry;
+ (void) registerAllExtensions:(PBMutableExtensionRegistry*) registry;
@end

#define Envelope_type @"type"
#define Envelope_source @"source"
#define Envelope_sourceDevice @"sourceDevice"
#define Envelope_relay @"relay"
#define Envelope_timestamp @"timestamp"
#define Envelope_legacyMessage @"legacyMessage"
#define Envelope_content @"content"
@interface SSKProtoEnvelope : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasTimestamp_:1;
  BOOL hasSource_:1;
  BOOL hasRelay_:1;
  BOOL hasLegacyMessage_:1;
  BOOL hasContent_:1;
  BOOL hasSourceDevice_:1;
  BOOL hasType_:1;
  UInt64 timestamp;
  NSString* source;
  NSString* relay;
  NSData* legacyMessage;
  NSData* content;
  UInt32 sourceDevice;
  SSKProtoEnvelopeType type;
}
- (BOOL) hasType;
- (BOOL) hasSource;
- (BOOL) hasSourceDevice;
- (BOOL) hasRelay;
- (BOOL) hasTimestamp;
- (BOOL) hasLegacyMessage;
- (BOOL) hasContent;
@property (readonly) SSKProtoEnvelopeType type;
@property (readonly, strong) NSString* source;
@property (readonly) UInt32 sourceDevice;
@property (readonly, strong) NSString* relay;
@property (readonly) UInt64 timestamp;
@property (readonly, strong) NSData* legacyMessage;
@property (readonly, strong) NSData* content;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoEnvelopeBuilder*) builder;
+ (SSKProtoEnvelopeBuilder*) builder;
+ (SSKProtoEnvelopeBuilder*) builderWithPrototype:(SSKProtoEnvelope*) prototype;
- (SSKProtoEnvelopeBuilder*) toBuilder;

+ (SSKProtoEnvelope*) parseFromData:(NSData*) data;
+ (SSKProtoEnvelope*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoEnvelope*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoEnvelope*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoEnvelope*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoEnvelope*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoEnvelopeBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoEnvelope* resultEnvelope;
}

- (SSKProtoEnvelope*) defaultInstance;

- (SSKProtoEnvelopeBuilder*) clear;
- (SSKProtoEnvelopeBuilder*) clone;

- (SSKProtoEnvelope*) build;
- (SSKProtoEnvelope*) buildPartial;

- (SSKProtoEnvelopeBuilder*) mergeFrom:(SSKProtoEnvelope*) other;
- (SSKProtoEnvelopeBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoEnvelopeBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasType;
- (SSKProtoEnvelopeType) type;
- (SSKProtoEnvelopeBuilder*) setType:(SSKProtoEnvelopeType) value;
- (SSKProtoEnvelopeBuilder*) clearType;

- (BOOL) hasSource;
- (NSString*) source;
- (SSKProtoEnvelopeBuilder*) setSource:(NSString*) value;
- (SSKProtoEnvelopeBuilder*) clearSource;

- (BOOL) hasSourceDevice;
- (UInt32) sourceDevice;
- (SSKProtoEnvelopeBuilder*) setSourceDevice:(UInt32) value;
- (SSKProtoEnvelopeBuilder*) clearSourceDevice;

- (BOOL) hasRelay;
- (NSString*) relay;
- (SSKProtoEnvelopeBuilder*) setRelay:(NSString*) value;
- (SSKProtoEnvelopeBuilder*) clearRelay;

- (BOOL) hasTimestamp;
- (UInt64) timestamp;
- (SSKProtoEnvelopeBuilder*) setTimestamp:(UInt64) value;
- (SSKProtoEnvelopeBuilder*) clearTimestamp;

- (BOOL) hasLegacyMessage;
- (NSData*) legacyMessage;
- (SSKProtoEnvelopeBuilder*) setLegacyMessage:(NSData*) value;
- (SSKProtoEnvelopeBuilder*) clearLegacyMessage;

- (BOOL) hasContent;
- (NSData*) content;
- (SSKProtoEnvelopeBuilder*) setContent:(NSData*) value;
- (SSKProtoEnvelopeBuilder*) clearContent;
@end

#define Content_dataMessage @"dataMessage"
#define Content_syncMessage @"syncMessage"
#define Content_callMessage @"callMessage"
#define Content_nullMessage @"nullMessage"
#define Content_receiptMessage @"receiptMessage"
@interface SSKProtoContent : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasDataMessage_:1;
  BOOL hasSyncMessage_:1;
  BOOL hasCallMessage_:1;
  BOOL hasNullMessage_:1;
  BOOL hasReceiptMessage_:1;
  SSKProtoDataMessage* dataMessage;
  SSKProtoSyncMessage* syncMessage;
  SSKProtoCallMessage* callMessage;
  SSKProtoNullMessage* nullMessage;
  SSKProtoReceiptMessage* receiptMessage;
}
- (BOOL) hasDataMessage;
- (BOOL) hasSyncMessage;
- (BOOL) hasCallMessage;
- (BOOL) hasNullMessage;
- (BOOL) hasReceiptMessage;
@property (readonly, strong) SSKProtoDataMessage* dataMessage;
@property (readonly, strong) SSKProtoSyncMessage* syncMessage;
@property (readonly, strong) SSKProtoCallMessage* callMessage;
@property (readonly, strong) SSKProtoNullMessage* nullMessage;
@property (readonly, strong) SSKProtoReceiptMessage* receiptMessage;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoContentBuilder*) builder;
+ (SSKProtoContentBuilder*) builder;
+ (SSKProtoContentBuilder*) builderWithPrototype:(SSKProtoContent*) prototype;
- (SSKProtoContentBuilder*) toBuilder;

+ (SSKProtoContent*) parseFromData:(NSData*) data;
+ (SSKProtoContent*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContent*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoContent*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContent*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoContent*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoContentBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoContent* resultContent;
}

- (SSKProtoContent*) defaultInstance;

- (SSKProtoContentBuilder*) clear;
- (SSKProtoContentBuilder*) clone;

- (SSKProtoContent*) build;
- (SSKProtoContent*) buildPartial;

- (SSKProtoContentBuilder*) mergeFrom:(SSKProtoContent*) other;
- (SSKProtoContentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoContentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasDataMessage;
- (SSKProtoDataMessage*) dataMessage;
- (SSKProtoContentBuilder*) setDataMessage:(SSKProtoDataMessage*) value;
- (SSKProtoContentBuilder*) setDataMessageBuilder:(SSKProtoDataMessageBuilder*) builderForValue;
- (SSKProtoContentBuilder*) mergeDataMessage:(SSKProtoDataMessage*) value;
- (SSKProtoContentBuilder*) clearDataMessage;

- (BOOL) hasSyncMessage;
- (SSKProtoSyncMessage*) syncMessage;
- (SSKProtoContentBuilder*) setSyncMessage:(SSKProtoSyncMessage*) value;
- (SSKProtoContentBuilder*) setSyncMessageBuilder:(SSKProtoSyncMessageBuilder*) builderForValue;
- (SSKProtoContentBuilder*) mergeSyncMessage:(SSKProtoSyncMessage*) value;
- (SSKProtoContentBuilder*) clearSyncMessage;

- (BOOL) hasCallMessage;
- (SSKProtoCallMessage*) callMessage;
- (SSKProtoContentBuilder*) setCallMessage:(SSKProtoCallMessage*) value;
- (SSKProtoContentBuilder*) setCallMessageBuilder:(SSKProtoCallMessageBuilder*) builderForValue;
- (SSKProtoContentBuilder*) mergeCallMessage:(SSKProtoCallMessage*) value;
- (SSKProtoContentBuilder*) clearCallMessage;

- (BOOL) hasNullMessage;
- (SSKProtoNullMessage*) nullMessage;
- (SSKProtoContentBuilder*) setNullMessage:(SSKProtoNullMessage*) value;
- (SSKProtoContentBuilder*) setNullMessageBuilder:(SSKProtoNullMessageBuilder*) builderForValue;
- (SSKProtoContentBuilder*) mergeNullMessage:(SSKProtoNullMessage*) value;
- (SSKProtoContentBuilder*) clearNullMessage;

- (BOOL) hasReceiptMessage;
- (SSKProtoReceiptMessage*) receiptMessage;
- (SSKProtoContentBuilder*) setReceiptMessage:(SSKProtoReceiptMessage*) value;
- (SSKProtoContentBuilder*) setReceiptMessageBuilder:(SSKProtoReceiptMessageBuilder*) builderForValue;
- (SSKProtoContentBuilder*) mergeReceiptMessage:(SSKProtoReceiptMessage*) value;
- (SSKProtoContentBuilder*) clearReceiptMessage;
@end

#define CallMessage_offer @"offer"
#define CallMessage_answer @"answer"
#define CallMessage_iceUpdate @"iceUpdate"
#define CallMessage_hangup @"hangup"
#define CallMessage_busy @"busy"
#define CallMessage_profileKey @"profileKey"
@interface SSKProtoCallMessage : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasOffer_:1;
  BOOL hasAnswer_:1;
  BOOL hasHangup_:1;
  BOOL hasBusy_:1;
  BOOL hasProfileKey_:1;
  SSKProtoCallMessageOffer* offer;
  SSKProtoCallMessageAnswer* answer;
  SSKProtoCallMessageHangup* hangup;
  SSKProtoCallMessageBusy* busy;
  NSData* profileKey;
  NSMutableArray * iceUpdateArray;
}
- (BOOL) hasOffer;
- (BOOL) hasAnswer;
- (BOOL) hasHangup;
- (BOOL) hasBusy;
- (BOOL) hasProfileKey;
@property (readonly, strong) SSKProtoCallMessageOffer* offer;
@property (readonly, strong) SSKProtoCallMessageAnswer* answer;
@property (readonly, strong) NSArray<SSKProtoCallMessageIceUpdate*> * iceUpdate;
@property (readonly, strong) SSKProtoCallMessageHangup* hangup;
@property (readonly, strong) SSKProtoCallMessageBusy* busy;
@property (readonly, strong) NSData* profileKey;
- (SSKProtoCallMessageIceUpdate*)iceUpdateAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageBuilder*) builder;
+ (SSKProtoCallMessageBuilder*) builder;
+ (SSKProtoCallMessageBuilder*) builderWithPrototype:(SSKProtoCallMessage*) prototype;
- (SSKProtoCallMessageBuilder*) toBuilder;

+ (SSKProtoCallMessage*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessage*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Offer_id @"id"
#define Offer_sessionDescription @"sessionDescription"
@interface SSKProtoCallMessageOffer : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  BOOL hasSessionDescription_:1;
  UInt64 id;
  NSString* sessionDescription;
}
- (BOOL) hasId;
- (BOOL) hasSessionDescription;
@property (readonly) UInt64 id;
@property (readonly, strong) NSString* sessionDescription;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageOfferBuilder*) builder;
+ (SSKProtoCallMessageOfferBuilder*) builder;
+ (SSKProtoCallMessageOfferBuilder*) builderWithPrototype:(SSKProtoCallMessageOffer*) prototype;
- (SSKProtoCallMessageOfferBuilder*) toBuilder;

+ (SSKProtoCallMessageOffer*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessageOffer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageOffer*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessageOffer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageOffer*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessageOffer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoCallMessageOfferBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessageOffer* resultOffer;
}

- (SSKProtoCallMessageOffer*) defaultInstance;

- (SSKProtoCallMessageOfferBuilder*) clear;
- (SSKProtoCallMessageOfferBuilder*) clone;

- (SSKProtoCallMessageOffer*) build;
- (SSKProtoCallMessageOffer*) buildPartial;

- (SSKProtoCallMessageOfferBuilder*) mergeFrom:(SSKProtoCallMessageOffer*) other;
- (SSKProtoCallMessageOfferBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageOfferBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoCallMessageOfferBuilder*) setId:(UInt64) value;
- (SSKProtoCallMessageOfferBuilder*) clearId;

- (BOOL) hasSessionDescription;
- (NSString*) sessionDescription;
- (SSKProtoCallMessageOfferBuilder*) setSessionDescription:(NSString*) value;
- (SSKProtoCallMessageOfferBuilder*) clearSessionDescription;
@end

#define Answer_id @"id"
#define Answer_sessionDescription @"sessionDescription"
@interface SSKProtoCallMessageAnswer : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  BOOL hasSessionDescription_:1;
  UInt64 id;
  NSString* sessionDescription;
}
- (BOOL) hasId;
- (BOOL) hasSessionDescription;
@property (readonly) UInt64 id;
@property (readonly, strong) NSString* sessionDescription;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageAnswerBuilder*) builder;
+ (SSKProtoCallMessageAnswerBuilder*) builder;
+ (SSKProtoCallMessageAnswerBuilder*) builderWithPrototype:(SSKProtoCallMessageAnswer*) prototype;
- (SSKProtoCallMessageAnswerBuilder*) toBuilder;

+ (SSKProtoCallMessageAnswer*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessageAnswer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageAnswer*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessageAnswer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageAnswer*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessageAnswer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoCallMessageAnswerBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessageAnswer* resultAnswer;
}

- (SSKProtoCallMessageAnswer*) defaultInstance;

- (SSKProtoCallMessageAnswerBuilder*) clear;
- (SSKProtoCallMessageAnswerBuilder*) clone;

- (SSKProtoCallMessageAnswer*) build;
- (SSKProtoCallMessageAnswer*) buildPartial;

- (SSKProtoCallMessageAnswerBuilder*) mergeFrom:(SSKProtoCallMessageAnswer*) other;
- (SSKProtoCallMessageAnswerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageAnswerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoCallMessageAnswerBuilder*) setId:(UInt64) value;
- (SSKProtoCallMessageAnswerBuilder*) clearId;

- (BOOL) hasSessionDescription;
- (NSString*) sessionDescription;
- (SSKProtoCallMessageAnswerBuilder*) setSessionDescription:(NSString*) value;
- (SSKProtoCallMessageAnswerBuilder*) clearSessionDescription;
@end

#define IceUpdate_id @"id"
#define IceUpdate_sdpMid @"sdpMid"
#define IceUpdate_sdpMLineIndex @"sdpMlineIndex"
#define IceUpdate_sdp @"sdp"
@interface SSKProtoCallMessageIceUpdate : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  BOOL hasSdpMid_:1;
  BOOL hasSdp_:1;
  BOOL hasSdpMlineIndex_:1;
  UInt64 id;
  NSString* sdpMid;
  NSString* sdp;
  UInt32 sdpMlineIndex;
}
- (BOOL) hasId;
- (BOOL) hasSdpMid;
- (BOOL) hasSdpMlineIndex;
- (BOOL) hasSdp;
@property (readonly) UInt64 id;
@property (readonly, strong) NSString* sdpMid;
@property (readonly) UInt32 sdpMlineIndex;
@property (readonly, strong) NSString* sdp;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageIceUpdateBuilder*) builder;
+ (SSKProtoCallMessageIceUpdateBuilder*) builder;
+ (SSKProtoCallMessageIceUpdateBuilder*) builderWithPrototype:(SSKProtoCallMessageIceUpdate*) prototype;
- (SSKProtoCallMessageIceUpdateBuilder*) toBuilder;

+ (SSKProtoCallMessageIceUpdate*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessageIceUpdate*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageIceUpdate*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessageIceUpdate*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageIceUpdate*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessageIceUpdate*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoCallMessageIceUpdateBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessageIceUpdate* resultIceUpdate;
}

- (SSKProtoCallMessageIceUpdate*) defaultInstance;

- (SSKProtoCallMessageIceUpdateBuilder*) clear;
- (SSKProtoCallMessageIceUpdateBuilder*) clone;

- (SSKProtoCallMessageIceUpdate*) build;
- (SSKProtoCallMessageIceUpdate*) buildPartial;

- (SSKProtoCallMessageIceUpdateBuilder*) mergeFrom:(SSKProtoCallMessageIceUpdate*) other;
- (SSKProtoCallMessageIceUpdateBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageIceUpdateBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoCallMessageIceUpdateBuilder*) setId:(UInt64) value;
- (SSKProtoCallMessageIceUpdateBuilder*) clearId;

- (BOOL) hasSdpMid;
- (NSString*) sdpMid;
- (SSKProtoCallMessageIceUpdateBuilder*) setSdpMid:(NSString*) value;
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdpMid;

- (BOOL) hasSdpMlineIndex;
- (UInt32) sdpMlineIndex;
- (SSKProtoCallMessageIceUpdateBuilder*) setSdpMlineIndex:(UInt32) value;
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdpMlineIndex;

- (BOOL) hasSdp;
- (NSString*) sdp;
- (SSKProtoCallMessageIceUpdateBuilder*) setSdp:(NSString*) value;
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdp;
@end

#define Busy_id @"id"
@interface SSKProtoCallMessageBusy : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  UInt64 id;
}
- (BOOL) hasId;
@property (readonly) UInt64 id;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageBusyBuilder*) builder;
+ (SSKProtoCallMessageBusyBuilder*) builder;
+ (SSKProtoCallMessageBusyBuilder*) builderWithPrototype:(SSKProtoCallMessageBusy*) prototype;
- (SSKProtoCallMessageBusyBuilder*) toBuilder;

+ (SSKProtoCallMessageBusy*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessageBusy*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageBusy*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessageBusy*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageBusy*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessageBusy*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoCallMessageBusyBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessageBusy* resultBusy;
}

- (SSKProtoCallMessageBusy*) defaultInstance;

- (SSKProtoCallMessageBusyBuilder*) clear;
- (SSKProtoCallMessageBusyBuilder*) clone;

- (SSKProtoCallMessageBusy*) build;
- (SSKProtoCallMessageBusy*) buildPartial;

- (SSKProtoCallMessageBusyBuilder*) mergeFrom:(SSKProtoCallMessageBusy*) other;
- (SSKProtoCallMessageBusyBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageBusyBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoCallMessageBusyBuilder*) setId:(UInt64) value;
- (SSKProtoCallMessageBusyBuilder*) clearId;
@end

#define Hangup_id @"id"
@interface SSKProtoCallMessageHangup : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  UInt64 id;
}
- (BOOL) hasId;
@property (readonly) UInt64 id;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoCallMessageHangupBuilder*) builder;
+ (SSKProtoCallMessageHangupBuilder*) builder;
+ (SSKProtoCallMessageHangupBuilder*) builderWithPrototype:(SSKProtoCallMessageHangup*) prototype;
- (SSKProtoCallMessageHangupBuilder*) toBuilder;

+ (SSKProtoCallMessageHangup*) parseFromData:(NSData*) data;
+ (SSKProtoCallMessageHangup*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageHangup*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoCallMessageHangup*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoCallMessageHangup*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoCallMessageHangup*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoCallMessageHangupBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessageHangup* resultHangup;
}

- (SSKProtoCallMessageHangup*) defaultInstance;

- (SSKProtoCallMessageHangupBuilder*) clear;
- (SSKProtoCallMessageHangupBuilder*) clone;

- (SSKProtoCallMessageHangup*) build;
- (SSKProtoCallMessageHangup*) buildPartial;

- (SSKProtoCallMessageHangupBuilder*) mergeFrom:(SSKProtoCallMessageHangup*) other;
- (SSKProtoCallMessageHangupBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageHangupBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoCallMessageHangupBuilder*) setId:(UInt64) value;
- (SSKProtoCallMessageHangupBuilder*) clearId;
@end

@interface SSKProtoCallMessageBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoCallMessage* resultCallMessage;
}

- (SSKProtoCallMessage*) defaultInstance;

- (SSKProtoCallMessageBuilder*) clear;
- (SSKProtoCallMessageBuilder*) clone;

- (SSKProtoCallMessage*) build;
- (SSKProtoCallMessage*) buildPartial;

- (SSKProtoCallMessageBuilder*) mergeFrom:(SSKProtoCallMessage*) other;
- (SSKProtoCallMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoCallMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasOffer;
- (SSKProtoCallMessageOffer*) offer;
- (SSKProtoCallMessageBuilder*) setOffer:(SSKProtoCallMessageOffer*) value;
- (SSKProtoCallMessageBuilder*) setOfferBuilder:(SSKProtoCallMessageOfferBuilder*) builderForValue;
- (SSKProtoCallMessageBuilder*) mergeOffer:(SSKProtoCallMessageOffer*) value;
- (SSKProtoCallMessageBuilder*) clearOffer;

- (BOOL) hasAnswer;
- (SSKProtoCallMessageAnswer*) answer;
- (SSKProtoCallMessageBuilder*) setAnswer:(SSKProtoCallMessageAnswer*) value;
- (SSKProtoCallMessageBuilder*) setAnswerBuilder:(SSKProtoCallMessageAnswerBuilder*) builderForValue;
- (SSKProtoCallMessageBuilder*) mergeAnswer:(SSKProtoCallMessageAnswer*) value;
- (SSKProtoCallMessageBuilder*) clearAnswer;

- (NSMutableArray<SSKProtoCallMessageIceUpdate*> *)iceUpdate;
- (SSKProtoCallMessageIceUpdate*)iceUpdateAtIndex:(NSUInteger)index;
- (SSKProtoCallMessageBuilder *)addIceUpdate:(SSKProtoCallMessageIceUpdate*)value;
- (SSKProtoCallMessageBuilder *)setIceUpdateArray:(NSArray<SSKProtoCallMessageIceUpdate*> *)array;
- (SSKProtoCallMessageBuilder *)clearIceUpdate;

- (BOOL) hasHangup;
- (SSKProtoCallMessageHangup*) hangup;
- (SSKProtoCallMessageBuilder*) setHangup:(SSKProtoCallMessageHangup*) value;
- (SSKProtoCallMessageBuilder*) setHangupBuilder:(SSKProtoCallMessageHangupBuilder*) builderForValue;
- (SSKProtoCallMessageBuilder*) mergeHangup:(SSKProtoCallMessageHangup*) value;
- (SSKProtoCallMessageBuilder*) clearHangup;

- (BOOL) hasBusy;
- (SSKProtoCallMessageBusy*) busy;
- (SSKProtoCallMessageBuilder*) setBusy:(SSKProtoCallMessageBusy*) value;
- (SSKProtoCallMessageBuilder*) setBusyBuilder:(SSKProtoCallMessageBusyBuilder*) builderForValue;
- (SSKProtoCallMessageBuilder*) mergeBusy:(SSKProtoCallMessageBusy*) value;
- (SSKProtoCallMessageBuilder*) clearBusy;

- (BOOL) hasProfileKey;
- (NSData*) profileKey;
- (SSKProtoCallMessageBuilder*) setProfileKey:(NSData*) value;
- (SSKProtoCallMessageBuilder*) clearProfileKey;
@end

#define DataMessage_body @"body"
#define DataMessage_attachments @"attachments"
#define DataMessage_group @"group"
#define DataMessage_flags @"flags"
#define DataMessage_expireTimer @"expireTimer"
#define DataMessage_profileKey @"profileKey"
#define DataMessage_timestamp @"timestamp"
#define DataMessage_quote @"quote"
#define DataMessage_contact @"contact"
@interface SSKProtoDataMessage : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasTimestamp_:1;
  BOOL hasBody_:1;
  BOOL hasGroup_:1;
  BOOL hasQuote_:1;
  BOOL hasProfileKey_:1;
  BOOL hasFlags_:1;
  BOOL hasExpireTimer_:1;
  UInt64 timestamp;
  NSString* body;
  SSKProtoGroupContext* group;
  SSKProtoDataMessageQuote* quote;
  NSData* profileKey;
  UInt32 flags;
  UInt32 expireTimer;
  NSMutableArray * attachmentsArray;
  NSMutableArray * contactArray;
}
- (BOOL) hasBody;
- (BOOL) hasGroup;
- (BOOL) hasFlags;
- (BOOL) hasExpireTimer;
- (BOOL) hasProfileKey;
- (BOOL) hasTimestamp;
- (BOOL) hasQuote;
@property (readonly, strong) NSString* body;
@property (readonly, strong) NSArray<SSKProtoAttachmentPointer*> * attachments;
@property (readonly, strong) SSKProtoGroupContext* group;
@property (readonly) UInt32 flags;
@property (readonly) UInt32 expireTimer;
@property (readonly, strong) NSData* profileKey;
@property (readonly) UInt64 timestamp;
@property (readonly, strong) SSKProtoDataMessageQuote* quote;
@property (readonly, strong) NSArray<SSKProtoDataMessageContact*> * contact;
- (SSKProtoAttachmentPointer*)attachmentsAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContact*)contactAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageBuilder*) builder;
+ (SSKProtoDataMessageBuilder*) builder;
+ (SSKProtoDataMessageBuilder*) builderWithPrototype:(SSKProtoDataMessage*) prototype;
- (SSKProtoDataMessageBuilder*) toBuilder;

+ (SSKProtoDataMessage*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessage*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Quote_id @"id"
#define Quote_author @"author"
#define Quote_text @"text"
#define Quote_attachments @"attachments"
@interface SSKProtoDataMessageQuote : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  BOOL hasAuthor_:1;
  BOOL hasText_:1;
  UInt64 id;
  NSString* author;
  NSString* text;
  NSMutableArray * attachmentsArray;
}
- (BOOL) hasId;
- (BOOL) hasAuthor;
- (BOOL) hasText;
@property (readonly) UInt64 id;
@property (readonly, strong) NSString* author;
@property (readonly, strong) NSString* text;
@property (readonly, strong) NSArray<SSKProtoDataMessageQuoteQuotedAttachment*> * attachments;
- (SSKProtoDataMessageQuoteQuotedAttachment*)attachmentsAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageQuoteBuilder*) builder;
+ (SSKProtoDataMessageQuoteBuilder*) builder;
+ (SSKProtoDataMessageQuoteBuilder*) builderWithPrototype:(SSKProtoDataMessageQuote*) prototype;
- (SSKProtoDataMessageQuoteBuilder*) toBuilder;

+ (SSKProtoDataMessageQuote*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageQuote*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageQuote*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageQuote*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageQuote*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageQuote*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define QuotedAttachment_contentType @"contentType"
#define QuotedAttachment_fileName @"fileName"
#define QuotedAttachment_thumbnail @"thumbnail"
#define QuotedAttachment_flags @"flags"
@interface SSKProtoDataMessageQuoteQuotedAttachment : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasContentType_:1;
  BOOL hasFileName_:1;
  BOOL hasThumbnail_:1;
  BOOL hasFlags_:1;
  NSString* contentType;
  NSString* fileName;
  SSKProtoAttachmentPointer* thumbnail;
  UInt32 flags;
}
- (BOOL) hasContentType;
- (BOOL) hasFileName;
- (BOOL) hasThumbnail;
- (BOOL) hasFlags;
@property (readonly, strong) NSString* contentType;
@property (readonly, strong) NSString* fileName;
@property (readonly, strong) SSKProtoAttachmentPointer* thumbnail;
@property (readonly) UInt32 flags;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builder;
+ (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builder;
+ (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builderWithPrototype:(SSKProtoDataMessageQuoteQuotedAttachment*) prototype;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) toBuilder;

+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageQuoteQuotedAttachmentBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageQuoteQuotedAttachment* resultQuotedAttachment;
}

- (SSKProtoDataMessageQuoteQuotedAttachment*) defaultInstance;

- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clear;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clone;

- (SSKProtoDataMessageQuoteQuotedAttachment*) build;
- (SSKProtoDataMessageQuoteQuotedAttachment*) buildPartial;

- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFrom:(SSKProtoDataMessageQuoteQuotedAttachment*) other;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasContentType;
- (NSString*) contentType;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setContentType:(NSString*) value;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearContentType;

- (BOOL) hasFileName;
- (NSString*) fileName;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setFileName:(NSString*) value;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearFileName;

- (BOOL) hasThumbnail;
- (SSKProtoAttachmentPointer*) thumbnail;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setThumbnail:(SSKProtoAttachmentPointer*) value;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setThumbnailBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeThumbnail:(SSKProtoAttachmentPointer*) value;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearThumbnail;

- (BOOL) hasFlags;
- (UInt32) flags;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setFlags:(UInt32) value;
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearFlags;
@end

@interface SSKProtoDataMessageQuoteBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageQuote* resultQuote;
}

- (SSKProtoDataMessageQuote*) defaultInstance;

- (SSKProtoDataMessageQuoteBuilder*) clear;
- (SSKProtoDataMessageQuoteBuilder*) clone;

- (SSKProtoDataMessageQuote*) build;
- (SSKProtoDataMessageQuote*) buildPartial;

- (SSKProtoDataMessageQuoteBuilder*) mergeFrom:(SSKProtoDataMessageQuote*) other;
- (SSKProtoDataMessageQuoteBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageQuoteBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoDataMessageQuoteBuilder*) setId:(UInt64) value;
- (SSKProtoDataMessageQuoteBuilder*) clearId;

- (BOOL) hasAuthor;
- (NSString*) author;
- (SSKProtoDataMessageQuoteBuilder*) setAuthor:(NSString*) value;
- (SSKProtoDataMessageQuoteBuilder*) clearAuthor;

- (BOOL) hasText;
- (NSString*) text;
- (SSKProtoDataMessageQuoteBuilder*) setText:(NSString*) value;
- (SSKProtoDataMessageQuoteBuilder*) clearText;

- (NSMutableArray<SSKProtoDataMessageQuoteQuotedAttachment*> *)attachments;
- (SSKProtoDataMessageQuoteQuotedAttachment*)attachmentsAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageQuoteBuilder *)addAttachments:(SSKProtoDataMessageQuoteQuotedAttachment*)value;
- (SSKProtoDataMessageQuoteBuilder *)setAttachmentsArray:(NSArray<SSKProtoDataMessageQuoteQuotedAttachment*> *)array;
- (SSKProtoDataMessageQuoteBuilder *)clearAttachments;
@end

#define Contact_name @"name"
#define Contact_number @"number"
#define Contact_email @"email"
#define Contact_address @"address"
#define Contact_avatar @"avatar"
#define Contact_organization @"organization"
@interface SSKProtoDataMessageContact : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasOrganization_:1;
  BOOL hasName_:1;
  BOOL hasAvatar_:1;
  NSString* organization;
  SSKProtoDataMessageContactName* name;
  SSKProtoDataMessageContactAvatar* avatar;
  NSMutableArray * numberArray;
  NSMutableArray * emailArray;
  NSMutableArray * addressArray;
}
- (BOOL) hasName;
- (BOOL) hasAvatar;
- (BOOL) hasOrganization;
@property (readonly, strong) SSKProtoDataMessageContactName* name;
@property (readonly, strong) NSArray<SSKProtoDataMessageContactPhone*> * number;
@property (readonly, strong) NSArray<SSKProtoDataMessageContactEmail*> * email;
@property (readonly, strong) NSArray<SSKProtoDataMessageContactPostalAddress*> * address;
@property (readonly, strong) SSKProtoDataMessageContactAvatar* avatar;
@property (readonly, strong) NSString* organization;
- (SSKProtoDataMessageContactPhone*)numberAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContactEmail*)emailAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContactPostalAddress*)addressAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactBuilder*) builder;
+ (SSKProtoDataMessageContactBuilder*) builder;
+ (SSKProtoDataMessageContactBuilder*) builderWithPrototype:(SSKProtoDataMessageContact*) prototype;
- (SSKProtoDataMessageContactBuilder*) toBuilder;

+ (SSKProtoDataMessageContact*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContact*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContact*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContact*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContact*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContact*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Name_givenName @"givenName"
#define Name_familyName @"familyName"
#define Name_prefix @"prefix"
#define Name_suffix @"suffix"
#define Name_middleName @"middleName"
#define Name_displayName @"displayName"
@interface SSKProtoDataMessageContactName : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasGivenName_:1;
  BOOL hasFamilyName_:1;
  BOOL hasPrefix_:1;
  BOOL hasSuffix_:1;
  BOOL hasMiddleName_:1;
  BOOL hasDisplayName_:1;
  NSString* givenName;
  NSString* familyName;
  NSString* prefix;
  NSString* suffix;
  NSString* middleName;
  NSString* displayName;
}
- (BOOL) hasGivenName;
- (BOOL) hasFamilyName;
- (BOOL) hasPrefix;
- (BOOL) hasSuffix;
- (BOOL) hasMiddleName;
- (BOOL) hasDisplayName;
@property (readonly, strong) NSString* givenName;
@property (readonly, strong) NSString* familyName;
@property (readonly, strong) NSString* prefix;
@property (readonly, strong) NSString* suffix;
@property (readonly, strong) NSString* middleName;
@property (readonly, strong) NSString* displayName;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactNameBuilder*) builder;
+ (SSKProtoDataMessageContactNameBuilder*) builder;
+ (SSKProtoDataMessageContactNameBuilder*) builderWithPrototype:(SSKProtoDataMessageContactName*) prototype;
- (SSKProtoDataMessageContactNameBuilder*) toBuilder;

+ (SSKProtoDataMessageContactName*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContactName*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactName*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContactName*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactName*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContactName*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageContactNameBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContactName* resultName;
}

- (SSKProtoDataMessageContactName*) defaultInstance;

- (SSKProtoDataMessageContactNameBuilder*) clear;
- (SSKProtoDataMessageContactNameBuilder*) clone;

- (SSKProtoDataMessageContactName*) build;
- (SSKProtoDataMessageContactName*) buildPartial;

- (SSKProtoDataMessageContactNameBuilder*) mergeFrom:(SSKProtoDataMessageContactName*) other;
- (SSKProtoDataMessageContactNameBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactNameBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasGivenName;
- (NSString*) givenName;
- (SSKProtoDataMessageContactNameBuilder*) setGivenName:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearGivenName;

- (BOOL) hasFamilyName;
- (NSString*) familyName;
- (SSKProtoDataMessageContactNameBuilder*) setFamilyName:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearFamilyName;

- (BOOL) hasPrefix;
- (NSString*) prefix;
- (SSKProtoDataMessageContactNameBuilder*) setPrefix:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearPrefix;

- (BOOL) hasSuffix;
- (NSString*) suffix;
- (SSKProtoDataMessageContactNameBuilder*) setSuffix:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearSuffix;

- (BOOL) hasMiddleName;
- (NSString*) middleName;
- (SSKProtoDataMessageContactNameBuilder*) setMiddleName:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearMiddleName;

- (BOOL) hasDisplayName;
- (NSString*) displayName;
- (SSKProtoDataMessageContactNameBuilder*) setDisplayName:(NSString*) value;
- (SSKProtoDataMessageContactNameBuilder*) clearDisplayName;
@end

#define Phone_value @"value"
#define Phone_type @"type"
#define Phone_label @"label"
@interface SSKProtoDataMessageContactPhone : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasValue_:1;
  BOOL hasLabel_:1;
  BOOL hasType_:1;
  NSString* value;
  NSString* label;
  SSKProtoDataMessageContactPhoneType type;
}
- (BOOL) hasValue;
- (BOOL) hasType;
- (BOOL) hasLabel;
@property (readonly, strong) NSString* value;
@property (readonly) SSKProtoDataMessageContactPhoneType type;
@property (readonly, strong) NSString* label;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactPhoneBuilder*) builder;
+ (SSKProtoDataMessageContactPhoneBuilder*) builder;
+ (SSKProtoDataMessageContactPhoneBuilder*) builderWithPrototype:(SSKProtoDataMessageContactPhone*) prototype;
- (SSKProtoDataMessageContactPhoneBuilder*) toBuilder;

+ (SSKProtoDataMessageContactPhone*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContactPhone*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactPhone*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContactPhone*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactPhone*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContactPhone*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageContactPhoneBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContactPhone* resultPhone;
}

- (SSKProtoDataMessageContactPhone*) defaultInstance;

- (SSKProtoDataMessageContactPhoneBuilder*) clear;
- (SSKProtoDataMessageContactPhoneBuilder*) clone;

- (SSKProtoDataMessageContactPhone*) build;
- (SSKProtoDataMessageContactPhone*) buildPartial;

- (SSKProtoDataMessageContactPhoneBuilder*) mergeFrom:(SSKProtoDataMessageContactPhone*) other;
- (SSKProtoDataMessageContactPhoneBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactPhoneBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasValue;
- (NSString*) value;
- (SSKProtoDataMessageContactPhoneBuilder*) setValue:(NSString*) value;
- (SSKProtoDataMessageContactPhoneBuilder*) clearValue;

- (BOOL) hasType;
- (SSKProtoDataMessageContactPhoneType) type;
- (SSKProtoDataMessageContactPhoneBuilder*) setType:(SSKProtoDataMessageContactPhoneType) value;
- (SSKProtoDataMessageContactPhoneBuilder*) clearType;

- (BOOL) hasLabel;
- (NSString*) label;
- (SSKProtoDataMessageContactPhoneBuilder*) setLabel:(NSString*) value;
- (SSKProtoDataMessageContactPhoneBuilder*) clearLabel;
@end

#define Email_value @"value"
#define Email_type @"type"
#define Email_label @"label"
@interface SSKProtoDataMessageContactEmail : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasValue_:1;
  BOOL hasLabel_:1;
  BOOL hasType_:1;
  NSString* value;
  NSString* label;
  SSKProtoDataMessageContactEmailType type;
}
- (BOOL) hasValue;
- (BOOL) hasType;
- (BOOL) hasLabel;
@property (readonly, strong) NSString* value;
@property (readonly) SSKProtoDataMessageContactEmailType type;
@property (readonly, strong) NSString* label;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactEmailBuilder*) builder;
+ (SSKProtoDataMessageContactEmailBuilder*) builder;
+ (SSKProtoDataMessageContactEmailBuilder*) builderWithPrototype:(SSKProtoDataMessageContactEmail*) prototype;
- (SSKProtoDataMessageContactEmailBuilder*) toBuilder;

+ (SSKProtoDataMessageContactEmail*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContactEmail*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactEmail*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContactEmail*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactEmail*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContactEmail*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageContactEmailBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContactEmail* resultEmail;
}

- (SSKProtoDataMessageContactEmail*) defaultInstance;

- (SSKProtoDataMessageContactEmailBuilder*) clear;
- (SSKProtoDataMessageContactEmailBuilder*) clone;

- (SSKProtoDataMessageContactEmail*) build;
- (SSKProtoDataMessageContactEmail*) buildPartial;

- (SSKProtoDataMessageContactEmailBuilder*) mergeFrom:(SSKProtoDataMessageContactEmail*) other;
- (SSKProtoDataMessageContactEmailBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactEmailBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasValue;
- (NSString*) value;
- (SSKProtoDataMessageContactEmailBuilder*) setValue:(NSString*) value;
- (SSKProtoDataMessageContactEmailBuilder*) clearValue;

- (BOOL) hasType;
- (SSKProtoDataMessageContactEmailType) type;
- (SSKProtoDataMessageContactEmailBuilder*) setType:(SSKProtoDataMessageContactEmailType) value;
- (SSKProtoDataMessageContactEmailBuilder*) clearType;

- (BOOL) hasLabel;
- (NSString*) label;
- (SSKProtoDataMessageContactEmailBuilder*) setLabel:(NSString*) value;
- (SSKProtoDataMessageContactEmailBuilder*) clearLabel;
@end

#define PostalAddress_type @"type"
#define PostalAddress_label @"label"
#define PostalAddress_street @"street"
#define PostalAddress_pobox @"pobox"
#define PostalAddress_neighborhood @"neighborhood"
#define PostalAddress_city @"city"
#define PostalAddress_region @"region"
#define PostalAddress_postcode @"postcode"
#define PostalAddress_country @"country"
@interface SSKProtoDataMessageContactPostalAddress : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasLabel_:1;
  BOOL hasStreet_:1;
  BOOL hasPobox_:1;
  BOOL hasNeighborhood_:1;
  BOOL hasCity_:1;
  BOOL hasRegion_:1;
  BOOL hasPostcode_:1;
  BOOL hasCountry_:1;
  BOOL hasType_:1;
  NSString* label;
  NSString* street;
  NSString* pobox;
  NSString* neighborhood;
  NSString* city;
  NSString* region;
  NSString* postcode;
  NSString* country;
  SSKProtoDataMessageContactPostalAddressType type;
}
- (BOOL) hasType;
- (BOOL) hasLabel;
- (BOOL) hasStreet;
- (BOOL) hasPobox;
- (BOOL) hasNeighborhood;
- (BOOL) hasCity;
- (BOOL) hasRegion;
- (BOOL) hasPostcode;
- (BOOL) hasCountry;
@property (readonly) SSKProtoDataMessageContactPostalAddressType type;
@property (readonly, strong) NSString* label;
@property (readonly, strong) NSString* street;
@property (readonly, strong) NSString* pobox;
@property (readonly, strong) NSString* neighborhood;
@property (readonly, strong) NSString* city;
@property (readonly, strong) NSString* region;
@property (readonly, strong) NSString* postcode;
@property (readonly, strong) NSString* country;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactPostalAddressBuilder*) builder;
+ (SSKProtoDataMessageContactPostalAddressBuilder*) builder;
+ (SSKProtoDataMessageContactPostalAddressBuilder*) builderWithPrototype:(SSKProtoDataMessageContactPostalAddress*) prototype;
- (SSKProtoDataMessageContactPostalAddressBuilder*) toBuilder;

+ (SSKProtoDataMessageContactPostalAddress*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContactPostalAddress*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactPostalAddress*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContactPostalAddress*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactPostalAddress*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContactPostalAddress*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageContactPostalAddressBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContactPostalAddress* resultPostalAddress;
}

- (SSKProtoDataMessageContactPostalAddress*) defaultInstance;

- (SSKProtoDataMessageContactPostalAddressBuilder*) clear;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clone;

- (SSKProtoDataMessageContactPostalAddress*) build;
- (SSKProtoDataMessageContactPostalAddress*) buildPartial;

- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFrom:(SSKProtoDataMessageContactPostalAddress*) other;
- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasType;
- (SSKProtoDataMessageContactPostalAddressType) type;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setType:(SSKProtoDataMessageContactPostalAddressType) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearType;

- (BOOL) hasLabel;
- (NSString*) label;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setLabel:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearLabel;

- (BOOL) hasStreet;
- (NSString*) street;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setStreet:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearStreet;

- (BOOL) hasPobox;
- (NSString*) pobox;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setPobox:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearPobox;

- (BOOL) hasNeighborhood;
- (NSString*) neighborhood;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setNeighborhood:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearNeighborhood;

- (BOOL) hasCity;
- (NSString*) city;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setCity:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearCity;

- (BOOL) hasRegion;
- (NSString*) region;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setRegion:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearRegion;

- (BOOL) hasPostcode;
- (NSString*) postcode;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setPostcode:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearPostcode;

- (BOOL) hasCountry;
- (NSString*) country;
- (SSKProtoDataMessageContactPostalAddressBuilder*) setCountry:(NSString*) value;
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearCountry;
@end

#define Avatar_avatar @"avatar"
#define Avatar_isProfile @"isProfile"
@interface SSKProtoDataMessageContactAvatar : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasIsProfile_:1;
  BOOL hasAvatar_:1;
  BOOL isProfile_:1;
  SSKProtoAttachmentPointer* avatar;
}
- (BOOL) hasAvatar;
- (BOOL) hasIsProfile;
@property (readonly, strong) SSKProtoAttachmentPointer* avatar;
- (BOOL) isProfile;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoDataMessageContactAvatarBuilder*) builder;
+ (SSKProtoDataMessageContactAvatarBuilder*) builder;
+ (SSKProtoDataMessageContactAvatarBuilder*) builderWithPrototype:(SSKProtoDataMessageContactAvatar*) prototype;
- (SSKProtoDataMessageContactAvatarBuilder*) toBuilder;

+ (SSKProtoDataMessageContactAvatar*) parseFromData:(NSData*) data;
+ (SSKProtoDataMessageContactAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactAvatar*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoDataMessageContactAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoDataMessageContactAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoDataMessageContactAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoDataMessageContactAvatarBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContactAvatar* resultAvatar;
}

- (SSKProtoDataMessageContactAvatar*) defaultInstance;

- (SSKProtoDataMessageContactAvatarBuilder*) clear;
- (SSKProtoDataMessageContactAvatarBuilder*) clone;

- (SSKProtoDataMessageContactAvatar*) build;
- (SSKProtoDataMessageContactAvatar*) buildPartial;

- (SSKProtoDataMessageContactAvatarBuilder*) mergeFrom:(SSKProtoDataMessageContactAvatar*) other;
- (SSKProtoDataMessageContactAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasAvatar;
- (SSKProtoAttachmentPointer*) avatar;
- (SSKProtoDataMessageContactAvatarBuilder*) setAvatar:(SSKProtoAttachmentPointer*) value;
- (SSKProtoDataMessageContactAvatarBuilder*) setAvatarBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue;
- (SSKProtoDataMessageContactAvatarBuilder*) mergeAvatar:(SSKProtoAttachmentPointer*) value;
- (SSKProtoDataMessageContactAvatarBuilder*) clearAvatar;

- (BOOL) hasIsProfile;
- (BOOL) isProfile;
- (SSKProtoDataMessageContactAvatarBuilder*) setIsProfile:(BOOL) value;
- (SSKProtoDataMessageContactAvatarBuilder*) clearIsProfile;
@end

@interface SSKProtoDataMessageContactBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessageContact* resultContact;
}

- (SSKProtoDataMessageContact*) defaultInstance;

- (SSKProtoDataMessageContactBuilder*) clear;
- (SSKProtoDataMessageContactBuilder*) clone;

- (SSKProtoDataMessageContact*) build;
- (SSKProtoDataMessageContact*) buildPartial;

- (SSKProtoDataMessageContactBuilder*) mergeFrom:(SSKProtoDataMessageContact*) other;
- (SSKProtoDataMessageContactBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageContactBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasName;
- (SSKProtoDataMessageContactName*) name;
- (SSKProtoDataMessageContactBuilder*) setName:(SSKProtoDataMessageContactName*) value;
- (SSKProtoDataMessageContactBuilder*) setNameBuilder:(SSKProtoDataMessageContactNameBuilder*) builderForValue;
- (SSKProtoDataMessageContactBuilder*) mergeName:(SSKProtoDataMessageContactName*) value;
- (SSKProtoDataMessageContactBuilder*) clearName;

- (NSMutableArray<SSKProtoDataMessageContactPhone*> *)number;
- (SSKProtoDataMessageContactPhone*)numberAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContactBuilder *)addNumber:(SSKProtoDataMessageContactPhone*)value;
- (SSKProtoDataMessageContactBuilder *)setNumberArray:(NSArray<SSKProtoDataMessageContactPhone*> *)array;
- (SSKProtoDataMessageContactBuilder *)clearNumber;

- (NSMutableArray<SSKProtoDataMessageContactEmail*> *)email;
- (SSKProtoDataMessageContactEmail*)emailAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContactBuilder *)addEmail:(SSKProtoDataMessageContactEmail*)value;
- (SSKProtoDataMessageContactBuilder *)setEmailArray:(NSArray<SSKProtoDataMessageContactEmail*> *)array;
- (SSKProtoDataMessageContactBuilder *)clearEmail;

- (NSMutableArray<SSKProtoDataMessageContactPostalAddress*> *)address;
- (SSKProtoDataMessageContactPostalAddress*)addressAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageContactBuilder *)addAddress:(SSKProtoDataMessageContactPostalAddress*)value;
- (SSKProtoDataMessageContactBuilder *)setAddressArray:(NSArray<SSKProtoDataMessageContactPostalAddress*> *)array;
- (SSKProtoDataMessageContactBuilder *)clearAddress;

- (BOOL) hasAvatar;
- (SSKProtoDataMessageContactAvatar*) avatar;
- (SSKProtoDataMessageContactBuilder*) setAvatar:(SSKProtoDataMessageContactAvatar*) value;
- (SSKProtoDataMessageContactBuilder*) setAvatarBuilder:(SSKProtoDataMessageContactAvatarBuilder*) builderForValue;
- (SSKProtoDataMessageContactBuilder*) mergeAvatar:(SSKProtoDataMessageContactAvatar*) value;
- (SSKProtoDataMessageContactBuilder*) clearAvatar;

- (BOOL) hasOrganization;
- (NSString*) organization;
- (SSKProtoDataMessageContactBuilder*) setOrganization:(NSString*) value;
- (SSKProtoDataMessageContactBuilder*) clearOrganization;
@end

@interface SSKProtoDataMessageBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoDataMessage* resultDataMessage;
}

- (SSKProtoDataMessage*) defaultInstance;

- (SSKProtoDataMessageBuilder*) clear;
- (SSKProtoDataMessageBuilder*) clone;

- (SSKProtoDataMessage*) build;
- (SSKProtoDataMessage*) buildPartial;

- (SSKProtoDataMessageBuilder*) mergeFrom:(SSKProtoDataMessage*) other;
- (SSKProtoDataMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoDataMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasBody;
- (NSString*) body;
- (SSKProtoDataMessageBuilder*) setBody:(NSString*) value;
- (SSKProtoDataMessageBuilder*) clearBody;

- (NSMutableArray<SSKProtoAttachmentPointer*> *)attachments;
- (SSKProtoAttachmentPointer*)attachmentsAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageBuilder *)addAttachments:(SSKProtoAttachmentPointer*)value;
- (SSKProtoDataMessageBuilder *)setAttachmentsArray:(NSArray<SSKProtoAttachmentPointer*> *)array;
- (SSKProtoDataMessageBuilder *)clearAttachments;

- (BOOL) hasGroup;
- (SSKProtoGroupContext*) group;
- (SSKProtoDataMessageBuilder*) setGroup:(SSKProtoGroupContext*) value;
- (SSKProtoDataMessageBuilder*) setGroupBuilder:(SSKProtoGroupContextBuilder*) builderForValue;
- (SSKProtoDataMessageBuilder*) mergeGroup:(SSKProtoGroupContext*) value;
- (SSKProtoDataMessageBuilder*) clearGroup;

- (BOOL) hasFlags;
- (UInt32) flags;
- (SSKProtoDataMessageBuilder*) setFlags:(UInt32) value;
- (SSKProtoDataMessageBuilder*) clearFlags;

- (BOOL) hasExpireTimer;
- (UInt32) expireTimer;
- (SSKProtoDataMessageBuilder*) setExpireTimer:(UInt32) value;
- (SSKProtoDataMessageBuilder*) clearExpireTimer;

- (BOOL) hasProfileKey;
- (NSData*) profileKey;
- (SSKProtoDataMessageBuilder*) setProfileKey:(NSData*) value;
- (SSKProtoDataMessageBuilder*) clearProfileKey;

- (BOOL) hasTimestamp;
- (UInt64) timestamp;
- (SSKProtoDataMessageBuilder*) setTimestamp:(UInt64) value;
- (SSKProtoDataMessageBuilder*) clearTimestamp;

- (BOOL) hasQuote;
- (SSKProtoDataMessageQuote*) quote;
- (SSKProtoDataMessageBuilder*) setQuote:(SSKProtoDataMessageQuote*) value;
- (SSKProtoDataMessageBuilder*) setQuoteBuilder:(SSKProtoDataMessageQuoteBuilder*) builderForValue;
- (SSKProtoDataMessageBuilder*) mergeQuote:(SSKProtoDataMessageQuote*) value;
- (SSKProtoDataMessageBuilder*) clearQuote;

- (NSMutableArray<SSKProtoDataMessageContact*> *)contact;
- (SSKProtoDataMessageContact*)contactAtIndex:(NSUInteger)index;
- (SSKProtoDataMessageBuilder *)addContact:(SSKProtoDataMessageContact*)value;
- (SSKProtoDataMessageBuilder *)setContactArray:(NSArray<SSKProtoDataMessageContact*> *)array;
- (SSKProtoDataMessageBuilder *)clearContact;
@end

#define NullMessage_padding @"padding"
@interface SSKProtoNullMessage : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasPadding_:1;
  NSData* padding;
}
- (BOOL) hasPadding;
@property (readonly, strong) NSData* padding;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoNullMessageBuilder*) builder;
+ (SSKProtoNullMessageBuilder*) builder;
+ (SSKProtoNullMessageBuilder*) builderWithPrototype:(SSKProtoNullMessage*) prototype;
- (SSKProtoNullMessageBuilder*) toBuilder;

+ (SSKProtoNullMessage*) parseFromData:(NSData*) data;
+ (SSKProtoNullMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoNullMessage*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoNullMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoNullMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoNullMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoNullMessageBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoNullMessage* resultNullMessage;
}

- (SSKProtoNullMessage*) defaultInstance;

- (SSKProtoNullMessageBuilder*) clear;
- (SSKProtoNullMessageBuilder*) clone;

- (SSKProtoNullMessage*) build;
- (SSKProtoNullMessage*) buildPartial;

- (SSKProtoNullMessageBuilder*) mergeFrom:(SSKProtoNullMessage*) other;
- (SSKProtoNullMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoNullMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasPadding;
- (NSData*) padding;
- (SSKProtoNullMessageBuilder*) setPadding:(NSData*) value;
- (SSKProtoNullMessageBuilder*) clearPadding;
@end

#define ReceiptMessage_type @"type"
#define ReceiptMessage_timestamp @"timestamp"
@interface SSKProtoReceiptMessage : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasType_:1;
  SSKProtoReceiptMessageType type;
  PBAppendableArray * timestampArray;
}
- (BOOL) hasType;
@property (readonly) SSKProtoReceiptMessageType type;
@property (readonly, strong) PBArray * timestamp;
- (UInt64)timestampAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoReceiptMessageBuilder*) builder;
+ (SSKProtoReceiptMessageBuilder*) builder;
+ (SSKProtoReceiptMessageBuilder*) builderWithPrototype:(SSKProtoReceiptMessage*) prototype;
- (SSKProtoReceiptMessageBuilder*) toBuilder;

+ (SSKProtoReceiptMessage*) parseFromData:(NSData*) data;
+ (SSKProtoReceiptMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoReceiptMessage*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoReceiptMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoReceiptMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoReceiptMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoReceiptMessageBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoReceiptMessage* resultReceiptMessage;
}

- (SSKProtoReceiptMessage*) defaultInstance;

- (SSKProtoReceiptMessageBuilder*) clear;
- (SSKProtoReceiptMessageBuilder*) clone;

- (SSKProtoReceiptMessage*) build;
- (SSKProtoReceiptMessage*) buildPartial;

- (SSKProtoReceiptMessageBuilder*) mergeFrom:(SSKProtoReceiptMessage*) other;
- (SSKProtoReceiptMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoReceiptMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasType;
- (SSKProtoReceiptMessageType) type;
- (SSKProtoReceiptMessageBuilder*) setType:(SSKProtoReceiptMessageType) value;
- (SSKProtoReceiptMessageBuilder*) clearType;

- (PBAppendableArray *)timestamp;
- (UInt64)timestampAtIndex:(NSUInteger)index;
- (SSKProtoReceiptMessageBuilder *)addTimestamp:(UInt64)value;
- (SSKProtoReceiptMessageBuilder *)setTimestampArray:(NSArray *)array;
- (SSKProtoReceiptMessageBuilder *)setTimestampValues:(const UInt64 *)values count:(NSUInteger)count;
- (SSKProtoReceiptMessageBuilder *)clearTimestamp;
@end

#define Verified_destination @"destination"
#define Verified_identityKey @"identityKey"
#define Verified_state @"state"
#define Verified_nullMessage @"nullMessage"
@interface SSKProtoVerified : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasDestination_:1;
  BOOL hasIdentityKey_:1;
  BOOL hasNullMessage_:1;
  BOOL hasState_:1;
  NSString* destination;
  NSData* identityKey;
  NSData* nullMessage;
  SSKProtoVerifiedState state;
}
- (BOOL) hasDestination;
- (BOOL) hasIdentityKey;
- (BOOL) hasState;
- (BOOL) hasNullMessage;
@property (readonly, strong) NSString* destination;
@property (readonly, strong) NSData* identityKey;
@property (readonly) SSKProtoVerifiedState state;
@property (readonly, strong) NSData* nullMessage;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoVerifiedBuilder*) builder;
+ (SSKProtoVerifiedBuilder*) builder;
+ (SSKProtoVerifiedBuilder*) builderWithPrototype:(SSKProtoVerified*) prototype;
- (SSKProtoVerifiedBuilder*) toBuilder;

+ (SSKProtoVerified*) parseFromData:(NSData*) data;
+ (SSKProtoVerified*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoVerified*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoVerified*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoVerified*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoVerified*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoVerifiedBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoVerified* resultVerified;
}

- (SSKProtoVerified*) defaultInstance;

- (SSKProtoVerifiedBuilder*) clear;
- (SSKProtoVerifiedBuilder*) clone;

- (SSKProtoVerified*) build;
- (SSKProtoVerified*) buildPartial;

- (SSKProtoVerifiedBuilder*) mergeFrom:(SSKProtoVerified*) other;
- (SSKProtoVerifiedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoVerifiedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasDestination;
- (NSString*) destination;
- (SSKProtoVerifiedBuilder*) setDestination:(NSString*) value;
- (SSKProtoVerifiedBuilder*) clearDestination;

- (BOOL) hasIdentityKey;
- (NSData*) identityKey;
- (SSKProtoVerifiedBuilder*) setIdentityKey:(NSData*) value;
- (SSKProtoVerifiedBuilder*) clearIdentityKey;

- (BOOL) hasState;
- (SSKProtoVerifiedState) state;
- (SSKProtoVerifiedBuilder*) setState:(SSKProtoVerifiedState) value;
- (SSKProtoVerifiedBuilder*) clearState;

- (BOOL) hasNullMessage;
- (NSData*) nullMessage;
- (SSKProtoVerifiedBuilder*) setNullMessage:(NSData*) value;
- (SSKProtoVerifiedBuilder*) clearNullMessage;
@end

#define SyncMessage_sent @"sent"
#define SyncMessage_contacts @"contacts"
#define SyncMessage_groups @"groups"
#define SyncMessage_request @"request"
#define SyncMessage_read @"read"
#define SyncMessage_blocked @"blocked"
#define SyncMessage_verified @"verified"
#define SyncMessage_configuration @"configuration"
#define SyncMessage_padding @"padding"
@interface SSKProtoSyncMessage : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasSent_:1;
  BOOL hasContacts_:1;
  BOOL hasGroups_:1;
  BOOL hasRequest_:1;
  BOOL hasBlocked_:1;
  BOOL hasVerified_:1;
  BOOL hasConfiguration_:1;
  BOOL hasPadding_:1;
  SSKProtoSyncMessageSent* sent;
  SSKProtoSyncMessageContacts* contacts;
  SSKProtoSyncMessageGroups* groups;
  SSKProtoSyncMessageRequest* request;
  SSKProtoSyncMessageBlocked* blocked;
  SSKProtoVerified* verified;
  SSKProtoSyncMessageConfiguration* configuration;
  NSData* padding;
  NSMutableArray * readArray;
}
- (BOOL) hasSent;
- (BOOL) hasContacts;
- (BOOL) hasGroups;
- (BOOL) hasRequest;
- (BOOL) hasBlocked;
- (BOOL) hasVerified;
- (BOOL) hasConfiguration;
- (BOOL) hasPadding;
@property (readonly, strong) SSKProtoSyncMessageSent* sent;
@property (readonly, strong) SSKProtoSyncMessageContacts* contacts;
@property (readonly, strong) SSKProtoSyncMessageGroups* groups;
@property (readonly, strong) SSKProtoSyncMessageRequest* request;
@property (readonly, strong) NSArray<SSKProtoSyncMessageRead*> * read;
@property (readonly, strong) SSKProtoSyncMessageBlocked* blocked;
@property (readonly, strong) SSKProtoVerified* verified;
@property (readonly, strong) SSKProtoSyncMessageConfiguration* configuration;
@property (readonly, strong) NSData* padding;
- (SSKProtoSyncMessageRead*)readAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageBuilder*) builder;
+ (SSKProtoSyncMessageBuilder*) builder;
+ (SSKProtoSyncMessageBuilder*) builderWithPrototype:(SSKProtoSyncMessage*) prototype;
- (SSKProtoSyncMessageBuilder*) toBuilder;

+ (SSKProtoSyncMessage*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessage*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Sent_destination @"destination"
#define Sent_timestamp @"timestamp"
#define Sent_message @"message"
#define Sent_expirationStartTimestamp @"expirationStartTimestamp"
@interface SSKProtoSyncMessageSent : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasTimestamp_:1;
  BOOL hasExpirationStartTimestamp_:1;
  BOOL hasDestination_:1;
  BOOL hasMessage_:1;
  UInt64 timestamp;
  UInt64 expirationStartTimestamp;
  NSString* destination;
  SSKProtoDataMessage* message;
}
- (BOOL) hasDestination;
- (BOOL) hasTimestamp;
- (BOOL) hasMessage;
- (BOOL) hasExpirationStartTimestamp;
@property (readonly, strong) NSString* destination;
@property (readonly) UInt64 timestamp;
@property (readonly, strong) SSKProtoDataMessage* message;
@property (readonly) UInt64 expirationStartTimestamp;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageSentBuilder*) builder;
+ (SSKProtoSyncMessageSentBuilder*) builder;
+ (SSKProtoSyncMessageSentBuilder*) builderWithPrototype:(SSKProtoSyncMessageSent*) prototype;
- (SSKProtoSyncMessageSentBuilder*) toBuilder;

+ (SSKProtoSyncMessageSent*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageSent*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageSent*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageSent*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageSent*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageSent*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageSentBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageSent* resultSent;
}

- (SSKProtoSyncMessageSent*) defaultInstance;

- (SSKProtoSyncMessageSentBuilder*) clear;
- (SSKProtoSyncMessageSentBuilder*) clone;

- (SSKProtoSyncMessageSent*) build;
- (SSKProtoSyncMessageSent*) buildPartial;

- (SSKProtoSyncMessageSentBuilder*) mergeFrom:(SSKProtoSyncMessageSent*) other;
- (SSKProtoSyncMessageSentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageSentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasDestination;
- (NSString*) destination;
- (SSKProtoSyncMessageSentBuilder*) setDestination:(NSString*) value;
- (SSKProtoSyncMessageSentBuilder*) clearDestination;

- (BOOL) hasTimestamp;
- (UInt64) timestamp;
- (SSKProtoSyncMessageSentBuilder*) setTimestamp:(UInt64) value;
- (SSKProtoSyncMessageSentBuilder*) clearTimestamp;

- (BOOL) hasMessage;
- (SSKProtoDataMessage*) message;
- (SSKProtoSyncMessageSentBuilder*) setMessage:(SSKProtoDataMessage*) value;
- (SSKProtoSyncMessageSentBuilder*) setMessageBuilder:(SSKProtoDataMessageBuilder*) builderForValue;
- (SSKProtoSyncMessageSentBuilder*) mergeMessage:(SSKProtoDataMessage*) value;
- (SSKProtoSyncMessageSentBuilder*) clearMessage;

- (BOOL) hasExpirationStartTimestamp;
- (UInt64) expirationStartTimestamp;
- (SSKProtoSyncMessageSentBuilder*) setExpirationStartTimestamp:(UInt64) value;
- (SSKProtoSyncMessageSentBuilder*) clearExpirationStartTimestamp;
@end

#define Contacts_blob @"blob"
#define Contacts_isComplete @"isComplete"
@interface SSKProtoSyncMessageContacts : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasIsComplete_:1;
  BOOL hasBlob_:1;
  BOOL isComplete_:1;
  SSKProtoAttachmentPointer* blob;
}
- (BOOL) hasBlob;
- (BOOL) hasIsComplete;
@property (readonly, strong) SSKProtoAttachmentPointer* blob;
- (BOOL) isComplete;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageContactsBuilder*) builder;
+ (SSKProtoSyncMessageContactsBuilder*) builder;
+ (SSKProtoSyncMessageContactsBuilder*) builderWithPrototype:(SSKProtoSyncMessageContacts*) prototype;
- (SSKProtoSyncMessageContactsBuilder*) toBuilder;

+ (SSKProtoSyncMessageContacts*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageContacts*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageContacts*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageContacts*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageContacts*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageContacts*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageContactsBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageContacts* resultContacts;
}

- (SSKProtoSyncMessageContacts*) defaultInstance;

- (SSKProtoSyncMessageContactsBuilder*) clear;
- (SSKProtoSyncMessageContactsBuilder*) clone;

- (SSKProtoSyncMessageContacts*) build;
- (SSKProtoSyncMessageContacts*) buildPartial;

- (SSKProtoSyncMessageContactsBuilder*) mergeFrom:(SSKProtoSyncMessageContacts*) other;
- (SSKProtoSyncMessageContactsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageContactsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasBlob;
- (SSKProtoAttachmentPointer*) blob;
- (SSKProtoSyncMessageContactsBuilder*) setBlob:(SSKProtoAttachmentPointer*) value;
- (SSKProtoSyncMessageContactsBuilder*) setBlobBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue;
- (SSKProtoSyncMessageContactsBuilder*) mergeBlob:(SSKProtoAttachmentPointer*) value;
- (SSKProtoSyncMessageContactsBuilder*) clearBlob;

- (BOOL) hasIsComplete;
- (BOOL) isComplete;
- (SSKProtoSyncMessageContactsBuilder*) setIsComplete:(BOOL) value;
- (SSKProtoSyncMessageContactsBuilder*) clearIsComplete;
@end

#define Groups_blob @"blob"
@interface SSKProtoSyncMessageGroups : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasBlob_:1;
  SSKProtoAttachmentPointer* blob;
}
- (BOOL) hasBlob;
@property (readonly, strong) SSKProtoAttachmentPointer* blob;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageGroupsBuilder*) builder;
+ (SSKProtoSyncMessageGroupsBuilder*) builder;
+ (SSKProtoSyncMessageGroupsBuilder*) builderWithPrototype:(SSKProtoSyncMessageGroups*) prototype;
- (SSKProtoSyncMessageGroupsBuilder*) toBuilder;

+ (SSKProtoSyncMessageGroups*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageGroups*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageGroups*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageGroups*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageGroups*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageGroups*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageGroupsBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageGroups* resultGroups;
}

- (SSKProtoSyncMessageGroups*) defaultInstance;

- (SSKProtoSyncMessageGroupsBuilder*) clear;
- (SSKProtoSyncMessageGroupsBuilder*) clone;

- (SSKProtoSyncMessageGroups*) build;
- (SSKProtoSyncMessageGroups*) buildPartial;

- (SSKProtoSyncMessageGroupsBuilder*) mergeFrom:(SSKProtoSyncMessageGroups*) other;
- (SSKProtoSyncMessageGroupsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageGroupsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasBlob;
- (SSKProtoAttachmentPointer*) blob;
- (SSKProtoSyncMessageGroupsBuilder*) setBlob:(SSKProtoAttachmentPointer*) value;
- (SSKProtoSyncMessageGroupsBuilder*) setBlobBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue;
- (SSKProtoSyncMessageGroupsBuilder*) mergeBlob:(SSKProtoAttachmentPointer*) value;
- (SSKProtoSyncMessageGroupsBuilder*) clearBlob;
@end

#define Blocked_numbers @"numbers"
@interface SSKProtoSyncMessageBlocked : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  NSMutableArray * numbersArray;
}
@property (readonly, strong) NSArray * numbers;
- (NSString*)numbersAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageBlockedBuilder*) builder;
+ (SSKProtoSyncMessageBlockedBuilder*) builder;
+ (SSKProtoSyncMessageBlockedBuilder*) builderWithPrototype:(SSKProtoSyncMessageBlocked*) prototype;
- (SSKProtoSyncMessageBlockedBuilder*) toBuilder;

+ (SSKProtoSyncMessageBlocked*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageBlocked*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageBlocked*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageBlocked*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageBlocked*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageBlocked*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageBlockedBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageBlocked* resultBlocked;
}

- (SSKProtoSyncMessageBlocked*) defaultInstance;

- (SSKProtoSyncMessageBlockedBuilder*) clear;
- (SSKProtoSyncMessageBlockedBuilder*) clone;

- (SSKProtoSyncMessageBlocked*) build;
- (SSKProtoSyncMessageBlocked*) buildPartial;

- (SSKProtoSyncMessageBlockedBuilder*) mergeFrom:(SSKProtoSyncMessageBlocked*) other;
- (SSKProtoSyncMessageBlockedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageBlockedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (NSMutableArray *)numbers;
- (NSString*)numbersAtIndex:(NSUInteger)index;
- (SSKProtoSyncMessageBlockedBuilder *)addNumbers:(NSString*)value;
- (SSKProtoSyncMessageBlockedBuilder *)setNumbersArray:(NSArray *)array;
- (SSKProtoSyncMessageBlockedBuilder *)clearNumbers;
@end

#define Request_type @"type"
@interface SSKProtoSyncMessageRequest : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasType_:1;
  SSKProtoSyncMessageRequestType type;
}
- (BOOL) hasType;
@property (readonly) SSKProtoSyncMessageRequestType type;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageRequestBuilder*) builder;
+ (SSKProtoSyncMessageRequestBuilder*) builder;
+ (SSKProtoSyncMessageRequestBuilder*) builderWithPrototype:(SSKProtoSyncMessageRequest*) prototype;
- (SSKProtoSyncMessageRequestBuilder*) toBuilder;

+ (SSKProtoSyncMessageRequest*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageRequest*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageRequest*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageRequest*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageRequest*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageRequest*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageRequestBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageRequest* resultRequest;
}

- (SSKProtoSyncMessageRequest*) defaultInstance;

- (SSKProtoSyncMessageRequestBuilder*) clear;
- (SSKProtoSyncMessageRequestBuilder*) clone;

- (SSKProtoSyncMessageRequest*) build;
- (SSKProtoSyncMessageRequest*) buildPartial;

- (SSKProtoSyncMessageRequestBuilder*) mergeFrom:(SSKProtoSyncMessageRequest*) other;
- (SSKProtoSyncMessageRequestBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageRequestBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasType;
- (SSKProtoSyncMessageRequestType) type;
- (SSKProtoSyncMessageRequestBuilder*) setType:(SSKProtoSyncMessageRequestType) value;
- (SSKProtoSyncMessageRequestBuilder*) clearType;
@end

#define Read_sender @"sender"
#define Read_timestamp @"timestamp"
@interface SSKProtoSyncMessageRead : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasTimestamp_:1;
  BOOL hasSender_:1;
  UInt64 timestamp;
  NSString* sender;
}
- (BOOL) hasSender;
- (BOOL) hasTimestamp;
@property (readonly, strong) NSString* sender;
@property (readonly) UInt64 timestamp;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageReadBuilder*) builder;
+ (SSKProtoSyncMessageReadBuilder*) builder;
+ (SSKProtoSyncMessageReadBuilder*) builderWithPrototype:(SSKProtoSyncMessageRead*) prototype;
- (SSKProtoSyncMessageReadBuilder*) toBuilder;

+ (SSKProtoSyncMessageRead*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageRead*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageRead*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageRead*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageRead*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageRead*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageReadBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageRead* resultRead;
}

- (SSKProtoSyncMessageRead*) defaultInstance;

- (SSKProtoSyncMessageReadBuilder*) clear;
- (SSKProtoSyncMessageReadBuilder*) clone;

- (SSKProtoSyncMessageRead*) build;
- (SSKProtoSyncMessageRead*) buildPartial;

- (SSKProtoSyncMessageReadBuilder*) mergeFrom:(SSKProtoSyncMessageRead*) other;
- (SSKProtoSyncMessageReadBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageReadBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasSender;
- (NSString*) sender;
- (SSKProtoSyncMessageReadBuilder*) setSender:(NSString*) value;
- (SSKProtoSyncMessageReadBuilder*) clearSender;

- (BOOL) hasTimestamp;
- (UInt64) timestamp;
- (SSKProtoSyncMessageReadBuilder*) setTimestamp:(UInt64) value;
- (SSKProtoSyncMessageReadBuilder*) clearTimestamp;
@end

#define Configuration_readReceipts @"readReceipts"
@interface SSKProtoSyncMessageConfiguration : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasReadReceipts_:1;
  BOOL readReceipts_:1;
}
- (BOOL) hasReadReceipts;
- (BOOL) readReceipts;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoSyncMessageConfigurationBuilder*) builder;
+ (SSKProtoSyncMessageConfigurationBuilder*) builder;
+ (SSKProtoSyncMessageConfigurationBuilder*) builderWithPrototype:(SSKProtoSyncMessageConfiguration*) prototype;
- (SSKProtoSyncMessageConfigurationBuilder*) toBuilder;

+ (SSKProtoSyncMessageConfiguration*) parseFromData:(NSData*) data;
+ (SSKProtoSyncMessageConfiguration*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageConfiguration*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoSyncMessageConfiguration*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoSyncMessageConfiguration*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoSyncMessageConfiguration*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoSyncMessageConfigurationBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessageConfiguration* resultConfiguration;
}

- (SSKProtoSyncMessageConfiguration*) defaultInstance;

- (SSKProtoSyncMessageConfigurationBuilder*) clear;
- (SSKProtoSyncMessageConfigurationBuilder*) clone;

- (SSKProtoSyncMessageConfiguration*) build;
- (SSKProtoSyncMessageConfiguration*) buildPartial;

- (SSKProtoSyncMessageConfigurationBuilder*) mergeFrom:(SSKProtoSyncMessageConfiguration*) other;
- (SSKProtoSyncMessageConfigurationBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageConfigurationBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasReadReceipts;
- (BOOL) readReceipts;
- (SSKProtoSyncMessageConfigurationBuilder*) setReadReceipts:(BOOL) value;
- (SSKProtoSyncMessageConfigurationBuilder*) clearReadReceipts;
@end

@interface SSKProtoSyncMessageBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoSyncMessage* resultSyncMessage;
}

- (SSKProtoSyncMessage*) defaultInstance;

- (SSKProtoSyncMessageBuilder*) clear;
- (SSKProtoSyncMessageBuilder*) clone;

- (SSKProtoSyncMessage*) build;
- (SSKProtoSyncMessage*) buildPartial;

- (SSKProtoSyncMessageBuilder*) mergeFrom:(SSKProtoSyncMessage*) other;
- (SSKProtoSyncMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoSyncMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasSent;
- (SSKProtoSyncMessageSent*) sent;
- (SSKProtoSyncMessageBuilder*) setSent:(SSKProtoSyncMessageSent*) value;
- (SSKProtoSyncMessageBuilder*) setSentBuilder:(SSKProtoSyncMessageSentBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeSent:(SSKProtoSyncMessageSent*) value;
- (SSKProtoSyncMessageBuilder*) clearSent;

- (BOOL) hasContacts;
- (SSKProtoSyncMessageContacts*) contacts;
- (SSKProtoSyncMessageBuilder*) setContacts:(SSKProtoSyncMessageContacts*) value;
- (SSKProtoSyncMessageBuilder*) setContactsBuilder:(SSKProtoSyncMessageContactsBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeContacts:(SSKProtoSyncMessageContacts*) value;
- (SSKProtoSyncMessageBuilder*) clearContacts;

- (BOOL) hasGroups;
- (SSKProtoSyncMessageGroups*) groups;
- (SSKProtoSyncMessageBuilder*) setGroups:(SSKProtoSyncMessageGroups*) value;
- (SSKProtoSyncMessageBuilder*) setGroupsBuilder:(SSKProtoSyncMessageGroupsBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeGroups:(SSKProtoSyncMessageGroups*) value;
- (SSKProtoSyncMessageBuilder*) clearGroups;

- (BOOL) hasRequest;
- (SSKProtoSyncMessageRequest*) request;
- (SSKProtoSyncMessageBuilder*) setRequest:(SSKProtoSyncMessageRequest*) value;
- (SSKProtoSyncMessageBuilder*) setRequestBuilder:(SSKProtoSyncMessageRequestBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeRequest:(SSKProtoSyncMessageRequest*) value;
- (SSKProtoSyncMessageBuilder*) clearRequest;

- (NSMutableArray<SSKProtoSyncMessageRead*> *)read;
- (SSKProtoSyncMessageRead*)readAtIndex:(NSUInteger)index;
- (SSKProtoSyncMessageBuilder *)addRead:(SSKProtoSyncMessageRead*)value;
- (SSKProtoSyncMessageBuilder *)setReadArray:(NSArray<SSKProtoSyncMessageRead*> *)array;
- (SSKProtoSyncMessageBuilder *)clearRead;

- (BOOL) hasBlocked;
- (SSKProtoSyncMessageBlocked*) blocked;
- (SSKProtoSyncMessageBuilder*) setBlocked:(SSKProtoSyncMessageBlocked*) value;
- (SSKProtoSyncMessageBuilder*) setBlockedBuilder:(SSKProtoSyncMessageBlockedBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeBlocked:(SSKProtoSyncMessageBlocked*) value;
- (SSKProtoSyncMessageBuilder*) clearBlocked;

- (BOOL) hasVerified;
- (SSKProtoVerified*) verified;
- (SSKProtoSyncMessageBuilder*) setVerified:(SSKProtoVerified*) value;
- (SSKProtoSyncMessageBuilder*) setVerifiedBuilder:(SSKProtoVerifiedBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeVerified:(SSKProtoVerified*) value;
- (SSKProtoSyncMessageBuilder*) clearVerified;

- (BOOL) hasConfiguration;
- (SSKProtoSyncMessageConfiguration*) configuration;
- (SSKProtoSyncMessageBuilder*) setConfiguration:(SSKProtoSyncMessageConfiguration*) value;
- (SSKProtoSyncMessageBuilder*) setConfigurationBuilder:(SSKProtoSyncMessageConfigurationBuilder*) builderForValue;
- (SSKProtoSyncMessageBuilder*) mergeConfiguration:(SSKProtoSyncMessageConfiguration*) value;
- (SSKProtoSyncMessageBuilder*) clearConfiguration;

- (BOOL) hasPadding;
- (NSData*) padding;
- (SSKProtoSyncMessageBuilder*) setPadding:(NSData*) value;
- (SSKProtoSyncMessageBuilder*) clearPadding;
@end

#define AttachmentPointer_id @"id"
#define AttachmentPointer_contentType @"contentType"
#define AttachmentPointer_key @"key"
#define AttachmentPointer_size @"size"
#define AttachmentPointer_thumbnail @"thumbnail"
#define AttachmentPointer_digest @"digest"
#define AttachmentPointer_fileName @"fileName"
#define AttachmentPointer_flags @"flags"
#define AttachmentPointer_width @"width"
#define AttachmentPointer_height @"height"
@interface SSKProtoAttachmentPointer : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasId_:1;
  BOOL hasContentType_:1;
  BOOL hasFileName_:1;
  BOOL hasKey_:1;
  BOOL hasThumbnail_:1;
  BOOL hasDigest_:1;
  BOOL hasSize_:1;
  BOOL hasFlags_:1;
  BOOL hasWidth_:1;
  BOOL hasHeight_:1;
  UInt64 id;
  NSString* contentType;
  NSString* fileName;
  NSData* key;
  NSData* thumbnail;
  NSData* digest;
  UInt32 size;
  UInt32 flags;
  UInt32 width;
  UInt32 height;
}
- (BOOL) hasId;
- (BOOL) hasContentType;
- (BOOL) hasKey;
- (BOOL) hasSize;
- (BOOL) hasThumbnail;
- (BOOL) hasDigest;
- (BOOL) hasFileName;
- (BOOL) hasFlags;
- (BOOL) hasWidth;
- (BOOL) hasHeight;
@property (readonly) UInt64 id;
@property (readonly, strong) NSString* contentType;
@property (readonly, strong) NSData* key;
@property (readonly) UInt32 size;
@property (readonly, strong) NSData* thumbnail;
@property (readonly, strong) NSData* digest;
@property (readonly, strong) NSString* fileName;
@property (readonly) UInt32 flags;
@property (readonly) UInt32 width;
@property (readonly) UInt32 height;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoAttachmentPointerBuilder*) builder;
+ (SSKProtoAttachmentPointerBuilder*) builder;
+ (SSKProtoAttachmentPointerBuilder*) builderWithPrototype:(SSKProtoAttachmentPointer*) prototype;
- (SSKProtoAttachmentPointerBuilder*) toBuilder;

+ (SSKProtoAttachmentPointer*) parseFromData:(NSData*) data;
+ (SSKProtoAttachmentPointer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoAttachmentPointer*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoAttachmentPointer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoAttachmentPointer*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoAttachmentPointer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoAttachmentPointerBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoAttachmentPointer* resultAttachmentPointer;
}

- (SSKProtoAttachmentPointer*) defaultInstance;

- (SSKProtoAttachmentPointerBuilder*) clear;
- (SSKProtoAttachmentPointerBuilder*) clone;

- (SSKProtoAttachmentPointer*) build;
- (SSKProtoAttachmentPointer*) buildPartial;

- (SSKProtoAttachmentPointerBuilder*) mergeFrom:(SSKProtoAttachmentPointer*) other;
- (SSKProtoAttachmentPointerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoAttachmentPointerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (UInt64) id;
- (SSKProtoAttachmentPointerBuilder*) setId:(UInt64) value;
- (SSKProtoAttachmentPointerBuilder*) clearId;

- (BOOL) hasContentType;
- (NSString*) contentType;
- (SSKProtoAttachmentPointerBuilder*) setContentType:(NSString*) value;
- (SSKProtoAttachmentPointerBuilder*) clearContentType;

- (BOOL) hasKey;
- (NSData*) key;
- (SSKProtoAttachmentPointerBuilder*) setKey:(NSData*) value;
- (SSKProtoAttachmentPointerBuilder*) clearKey;

- (BOOL) hasSize;
- (UInt32) size;
- (SSKProtoAttachmentPointerBuilder*) setSize:(UInt32) value;
- (SSKProtoAttachmentPointerBuilder*) clearSize;

- (BOOL) hasThumbnail;
- (NSData*) thumbnail;
- (SSKProtoAttachmentPointerBuilder*) setThumbnail:(NSData*) value;
- (SSKProtoAttachmentPointerBuilder*) clearThumbnail;

- (BOOL) hasDigest;
- (NSData*) digest;
- (SSKProtoAttachmentPointerBuilder*) setDigest:(NSData*) value;
- (SSKProtoAttachmentPointerBuilder*) clearDigest;

- (BOOL) hasFileName;
- (NSString*) fileName;
- (SSKProtoAttachmentPointerBuilder*) setFileName:(NSString*) value;
- (SSKProtoAttachmentPointerBuilder*) clearFileName;

- (BOOL) hasFlags;
- (UInt32) flags;
- (SSKProtoAttachmentPointerBuilder*) setFlags:(UInt32) value;
- (SSKProtoAttachmentPointerBuilder*) clearFlags;

- (BOOL) hasWidth;
- (UInt32) width;
- (SSKProtoAttachmentPointerBuilder*) setWidth:(UInt32) value;
- (SSKProtoAttachmentPointerBuilder*) clearWidth;

- (BOOL) hasHeight;
- (UInt32) height;
- (SSKProtoAttachmentPointerBuilder*) setHeight:(UInt32) value;
- (SSKProtoAttachmentPointerBuilder*) clearHeight;
@end

#define GroupContext_id @"id"
#define GroupContext_type @"type"
#define GroupContext_name @"name"
#define GroupContext_members @"members"
#define GroupContext_avatar @"avatar"
@interface SSKProtoGroupContext : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasName_:1;
  BOOL hasAvatar_:1;
  BOOL hasId_:1;
  BOOL hasType_:1;
  NSString* name;
  SSKProtoAttachmentPointer* avatar;
  NSData* id;
  SSKProtoGroupContextType type;
  NSMutableArray * membersArray;
}
- (BOOL) hasId;
- (BOOL) hasType;
- (BOOL) hasName;
- (BOOL) hasAvatar;
@property (readonly, strong) NSData* id;
@property (readonly) SSKProtoGroupContextType type;
@property (readonly, strong) NSString* name;
@property (readonly, strong) NSArray * members;
@property (readonly, strong) SSKProtoAttachmentPointer* avatar;
- (NSString*)membersAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoGroupContextBuilder*) builder;
+ (SSKProtoGroupContextBuilder*) builder;
+ (SSKProtoGroupContextBuilder*) builderWithPrototype:(SSKProtoGroupContext*) prototype;
- (SSKProtoGroupContextBuilder*) toBuilder;

+ (SSKProtoGroupContext*) parseFromData:(NSData*) data;
+ (SSKProtoGroupContext*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupContext*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoGroupContext*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupContext*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoGroupContext*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoGroupContextBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoGroupContext* resultGroupContext;
}

- (SSKProtoGroupContext*) defaultInstance;

- (SSKProtoGroupContextBuilder*) clear;
- (SSKProtoGroupContextBuilder*) clone;

- (SSKProtoGroupContext*) build;
- (SSKProtoGroupContext*) buildPartial;

- (SSKProtoGroupContextBuilder*) mergeFrom:(SSKProtoGroupContext*) other;
- (SSKProtoGroupContextBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoGroupContextBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (NSData*) id;
- (SSKProtoGroupContextBuilder*) setId:(NSData*) value;
- (SSKProtoGroupContextBuilder*) clearId;

- (BOOL) hasType;
- (SSKProtoGroupContextType) type;
- (SSKProtoGroupContextBuilder*) setType:(SSKProtoGroupContextType) value;
- (SSKProtoGroupContextBuilder*) clearType;

- (BOOL) hasName;
- (NSString*) name;
- (SSKProtoGroupContextBuilder*) setName:(NSString*) value;
- (SSKProtoGroupContextBuilder*) clearName;

- (NSMutableArray *)members;
- (NSString*)membersAtIndex:(NSUInteger)index;
- (SSKProtoGroupContextBuilder *)addMembers:(NSString*)value;
- (SSKProtoGroupContextBuilder *)setMembersArray:(NSArray *)array;
- (SSKProtoGroupContextBuilder *)clearMembers;

- (BOOL) hasAvatar;
- (SSKProtoAttachmentPointer*) avatar;
- (SSKProtoGroupContextBuilder*) setAvatar:(SSKProtoAttachmentPointer*) value;
- (SSKProtoGroupContextBuilder*) setAvatarBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue;
- (SSKProtoGroupContextBuilder*) mergeAvatar:(SSKProtoAttachmentPointer*) value;
- (SSKProtoGroupContextBuilder*) clearAvatar;
@end

#define ContactDetails_number @"number"
#define ContactDetails_name @"name"
#define ContactDetails_avatar @"avatar"
#define ContactDetails_color @"color"
#define ContactDetails_verified @"verified"
#define ContactDetails_profileKey @"profileKey"
#define ContactDetails_blocked @"blocked"
#define ContactDetails_expireTimer @"expireTimer"
@interface SSKProtoContactDetails : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasBlocked_:1;
  BOOL hasNumber_:1;
  BOOL hasName_:1;
  BOOL hasColor_:1;
  BOOL hasAvatar_:1;
  BOOL hasVerified_:1;
  BOOL hasProfileKey_:1;
  BOOL hasExpireTimer_:1;
  BOOL blocked_:1;
  NSString* number;
  NSString* name;
  NSString* color;
  SSKProtoContactDetailsAvatar* avatar;
  SSKProtoVerified* verified;
  NSData* profileKey;
  UInt32 expireTimer;
}
- (BOOL) hasNumber;
- (BOOL) hasName;
- (BOOL) hasAvatar;
- (BOOL) hasColor;
- (BOOL) hasVerified;
- (BOOL) hasProfileKey;
- (BOOL) hasBlocked;
- (BOOL) hasExpireTimer;
@property (readonly, strong) NSString* number;
@property (readonly, strong) NSString* name;
@property (readonly, strong) SSKProtoContactDetailsAvatar* avatar;
@property (readonly, strong) NSString* color;
@property (readonly, strong) SSKProtoVerified* verified;
@property (readonly, strong) NSData* profileKey;
- (BOOL) blocked;
@property (readonly) UInt32 expireTimer;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoContactDetailsBuilder*) builder;
+ (SSKProtoContactDetailsBuilder*) builder;
+ (SSKProtoContactDetailsBuilder*) builderWithPrototype:(SSKProtoContactDetails*) prototype;
- (SSKProtoContactDetailsBuilder*) toBuilder;

+ (SSKProtoContactDetails*) parseFromData:(NSData*) data;
+ (SSKProtoContactDetails*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContactDetails*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoContactDetails*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContactDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoContactDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Avatar_contentType @"contentType"
#define Avatar_length @"length"
@interface SSKProtoContactDetailsAvatar : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasContentType_:1;
  BOOL hasLength_:1;
  NSString* contentType;
  UInt32 length;
}
- (BOOL) hasContentType;
- (BOOL) hasLength;
@property (readonly, strong) NSString* contentType;
@property (readonly) UInt32 length;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoContactDetailsAvatarBuilder*) builder;
+ (SSKProtoContactDetailsAvatarBuilder*) builder;
+ (SSKProtoContactDetailsAvatarBuilder*) builderWithPrototype:(SSKProtoContactDetailsAvatar*) prototype;
- (SSKProtoContactDetailsAvatarBuilder*) toBuilder;

+ (SSKProtoContactDetailsAvatar*) parseFromData:(NSData*) data;
+ (SSKProtoContactDetailsAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContactDetailsAvatar*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoContactDetailsAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoContactDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoContactDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoContactDetailsAvatarBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoContactDetailsAvatar* resultAvatar;
}

- (SSKProtoContactDetailsAvatar*) defaultInstance;

- (SSKProtoContactDetailsAvatarBuilder*) clear;
- (SSKProtoContactDetailsAvatarBuilder*) clone;

- (SSKProtoContactDetailsAvatar*) build;
- (SSKProtoContactDetailsAvatar*) buildPartial;

- (SSKProtoContactDetailsAvatarBuilder*) mergeFrom:(SSKProtoContactDetailsAvatar*) other;
- (SSKProtoContactDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoContactDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasContentType;
- (NSString*) contentType;
- (SSKProtoContactDetailsAvatarBuilder*) setContentType:(NSString*) value;
- (SSKProtoContactDetailsAvatarBuilder*) clearContentType;

- (BOOL) hasLength;
- (UInt32) length;
- (SSKProtoContactDetailsAvatarBuilder*) setLength:(UInt32) value;
- (SSKProtoContactDetailsAvatarBuilder*) clearLength;
@end

@interface SSKProtoContactDetailsBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoContactDetails* resultContactDetails;
}

- (SSKProtoContactDetails*) defaultInstance;

- (SSKProtoContactDetailsBuilder*) clear;
- (SSKProtoContactDetailsBuilder*) clone;

- (SSKProtoContactDetails*) build;
- (SSKProtoContactDetails*) buildPartial;

- (SSKProtoContactDetailsBuilder*) mergeFrom:(SSKProtoContactDetails*) other;
- (SSKProtoContactDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoContactDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasNumber;
- (NSString*) number;
- (SSKProtoContactDetailsBuilder*) setNumber:(NSString*) value;
- (SSKProtoContactDetailsBuilder*) clearNumber;

- (BOOL) hasName;
- (NSString*) name;
- (SSKProtoContactDetailsBuilder*) setName:(NSString*) value;
- (SSKProtoContactDetailsBuilder*) clearName;

- (BOOL) hasAvatar;
- (SSKProtoContactDetailsAvatar*) avatar;
- (SSKProtoContactDetailsBuilder*) setAvatar:(SSKProtoContactDetailsAvatar*) value;
- (SSKProtoContactDetailsBuilder*) setAvatarBuilder:(SSKProtoContactDetailsAvatarBuilder*) builderForValue;
- (SSKProtoContactDetailsBuilder*) mergeAvatar:(SSKProtoContactDetailsAvatar*) value;
- (SSKProtoContactDetailsBuilder*) clearAvatar;

- (BOOL) hasColor;
- (NSString*) color;
- (SSKProtoContactDetailsBuilder*) setColor:(NSString*) value;
- (SSKProtoContactDetailsBuilder*) clearColor;

- (BOOL) hasVerified;
- (SSKProtoVerified*) verified;
- (SSKProtoContactDetailsBuilder*) setVerified:(SSKProtoVerified*) value;
- (SSKProtoContactDetailsBuilder*) setVerifiedBuilder:(SSKProtoVerifiedBuilder*) builderForValue;
- (SSKProtoContactDetailsBuilder*) mergeVerified:(SSKProtoVerified*) value;
- (SSKProtoContactDetailsBuilder*) clearVerified;

- (BOOL) hasProfileKey;
- (NSData*) profileKey;
- (SSKProtoContactDetailsBuilder*) setProfileKey:(NSData*) value;
- (SSKProtoContactDetailsBuilder*) clearProfileKey;

- (BOOL) hasBlocked;
- (BOOL) blocked;
- (SSKProtoContactDetailsBuilder*) setBlocked:(BOOL) value;
- (SSKProtoContactDetailsBuilder*) clearBlocked;

- (BOOL) hasExpireTimer;
- (UInt32) expireTimer;
- (SSKProtoContactDetailsBuilder*) setExpireTimer:(UInt32) value;
- (SSKProtoContactDetailsBuilder*) clearExpireTimer;
@end

#define GroupDetails_id @"id"
#define GroupDetails_name @"name"
#define GroupDetails_members @"members"
#define GroupDetails_avatar @"avatar"
#define GroupDetails_active @"active"
#define GroupDetails_expireTimer @"expireTimer"
#define GroupDetails_color @"color"
@interface SSKProtoGroupDetails : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasActive_:1;
  BOOL hasName_:1;
  BOOL hasColor_:1;
  BOOL hasAvatar_:1;
  BOOL hasId_:1;
  BOOL hasExpireTimer_:1;
  BOOL active_:1;
  NSString* name;
  NSString* color;
  SSKProtoGroupDetailsAvatar* avatar;
  NSData* id;
  UInt32 expireTimer;
  NSMutableArray * membersArray;
}
- (BOOL) hasId;
- (BOOL) hasName;
- (BOOL) hasAvatar;
- (BOOL) hasActive;
- (BOOL) hasExpireTimer;
- (BOOL) hasColor;
@property (readonly, strong) NSData* id;
@property (readonly, strong) NSString* name;
@property (readonly, strong) NSArray * members;
@property (readonly, strong) SSKProtoGroupDetailsAvatar* avatar;
- (BOOL) active;
@property (readonly) UInt32 expireTimer;
@property (readonly, strong) NSString* color;
- (NSString*)membersAtIndex:(NSUInteger)index;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoGroupDetailsBuilder*) builder;
+ (SSKProtoGroupDetailsBuilder*) builder;
+ (SSKProtoGroupDetailsBuilder*) builderWithPrototype:(SSKProtoGroupDetails*) prototype;
- (SSKProtoGroupDetailsBuilder*) toBuilder;

+ (SSKProtoGroupDetails*) parseFromData:(NSData*) data;
+ (SSKProtoGroupDetails*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupDetails*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoGroupDetails*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoGroupDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

#define Avatar_contentType @"contentType"
#define Avatar_length @"length"
@interface SSKProtoGroupDetailsAvatar : PBGeneratedMessage<GeneratedMessageProtocol> {
@private
  BOOL hasContentType_:1;
  BOOL hasLength_:1;
  NSString* contentType;
  UInt32 length;
}
- (BOOL) hasContentType;
- (BOOL) hasLength;
@property (readonly, strong) NSString* contentType;
@property (readonly) UInt32 length;

+ (instancetype) defaultInstance;
- (instancetype) defaultInstance;

- (BOOL) isInitialized;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (SSKProtoGroupDetailsAvatarBuilder*) builder;
+ (SSKProtoGroupDetailsAvatarBuilder*) builder;
+ (SSKProtoGroupDetailsAvatarBuilder*) builderWithPrototype:(SSKProtoGroupDetailsAvatar*) prototype;
- (SSKProtoGroupDetailsAvatarBuilder*) toBuilder;

+ (SSKProtoGroupDetailsAvatar*) parseFromData:(NSData*) data;
+ (SSKProtoGroupDetailsAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupDetailsAvatar*) parseFromInputStream:(NSInputStream*) input;
+ (SSKProtoGroupDetailsAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
+ (SSKProtoGroupDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input;
+ (SSKProtoGroupDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;
@end

@interface SSKProtoGroupDetailsAvatarBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoGroupDetailsAvatar* resultAvatar;
}

- (SSKProtoGroupDetailsAvatar*) defaultInstance;

- (SSKProtoGroupDetailsAvatarBuilder*) clear;
- (SSKProtoGroupDetailsAvatarBuilder*) clone;

- (SSKProtoGroupDetailsAvatar*) build;
- (SSKProtoGroupDetailsAvatar*) buildPartial;

- (SSKProtoGroupDetailsAvatarBuilder*) mergeFrom:(SSKProtoGroupDetailsAvatar*) other;
- (SSKProtoGroupDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoGroupDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasContentType;
- (NSString*) contentType;
- (SSKProtoGroupDetailsAvatarBuilder*) setContentType:(NSString*) value;
- (SSKProtoGroupDetailsAvatarBuilder*) clearContentType;

- (BOOL) hasLength;
- (UInt32) length;
- (SSKProtoGroupDetailsAvatarBuilder*) setLength:(UInt32) value;
- (SSKProtoGroupDetailsAvatarBuilder*) clearLength;
@end

@interface SSKProtoGroupDetailsBuilder : PBGeneratedMessageBuilder {
@private
  SSKProtoGroupDetails* resultGroupDetails;
}

- (SSKProtoGroupDetails*) defaultInstance;

- (SSKProtoGroupDetailsBuilder*) clear;
- (SSKProtoGroupDetailsBuilder*) clone;

- (SSKProtoGroupDetails*) build;
- (SSKProtoGroupDetails*) buildPartial;

- (SSKProtoGroupDetailsBuilder*) mergeFrom:(SSKProtoGroupDetails*) other;
- (SSKProtoGroupDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (SSKProtoGroupDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry;

- (BOOL) hasId;
- (NSData*) id;
- (SSKProtoGroupDetailsBuilder*) setId:(NSData*) value;
- (SSKProtoGroupDetailsBuilder*) clearId;

- (BOOL) hasName;
- (NSString*) name;
- (SSKProtoGroupDetailsBuilder*) setName:(NSString*) value;
- (SSKProtoGroupDetailsBuilder*) clearName;

- (NSMutableArray *)members;
- (NSString*)membersAtIndex:(NSUInteger)index;
- (SSKProtoGroupDetailsBuilder *)addMembers:(NSString*)value;
- (SSKProtoGroupDetailsBuilder *)setMembersArray:(NSArray *)array;
- (SSKProtoGroupDetailsBuilder *)clearMembers;

- (BOOL) hasAvatar;
- (SSKProtoGroupDetailsAvatar*) avatar;
- (SSKProtoGroupDetailsBuilder*) setAvatar:(SSKProtoGroupDetailsAvatar*) value;
- (SSKProtoGroupDetailsBuilder*) setAvatarBuilder:(SSKProtoGroupDetailsAvatarBuilder*) builderForValue;
- (SSKProtoGroupDetailsBuilder*) mergeAvatar:(SSKProtoGroupDetailsAvatar*) value;
- (SSKProtoGroupDetailsBuilder*) clearAvatar;

- (BOOL) hasActive;
- (BOOL) active;
- (SSKProtoGroupDetailsBuilder*) setActive:(BOOL) value;
- (SSKProtoGroupDetailsBuilder*) clearActive;

- (BOOL) hasExpireTimer;
- (UInt32) expireTimer;
- (SSKProtoGroupDetailsBuilder*) setExpireTimer:(UInt32) value;
- (SSKProtoGroupDetailsBuilder*) clearExpireTimer;

- (BOOL) hasColor;
- (NSString*) color;
- (SSKProtoGroupDetailsBuilder*) setColor:(NSString*) value;
- (SSKProtoGroupDetailsBuilder*) clearColor;
@end


// @@protoc_insertion_point(global_scope)
