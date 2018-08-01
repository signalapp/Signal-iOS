//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SignalServiceKit-Swift.h>

// @@protoc_insertion_point(imports)

@implementation OWSSignalServiceProtosSSKProtoRoot
static PBExtensionRegistry* extensionRegistry = nil;
+ (PBExtensionRegistry*) extensionRegistry {
  return extensionRegistry;
}

+ (void) initialize {
  if (self == [OWSSignalServiceProtosSSKProtoRoot class]) {
    PBMutableExtensionRegistry* registry = [PBMutableExtensionRegistry registry];
    [self registerAllExtensions:registry];
    [ObjectivecDescriptorRoot registerAllExtensions:registry];
    extensionRegistry = registry;
  }
}
+ (void) registerAllExtensions:(PBMutableExtensionRegistry*) registry {
}
@end

@interface SSKProtoEnvelope ()
@property SSKProtoEnvelopeType type;
@property (strong) NSString* source;
@property UInt32 sourceDevice;
@property (strong) NSString* relay;
@property UInt64 timestamp;
@property (strong) NSData* legacyMessage;
@property (strong) NSData* content;
@end

@implementation SSKProtoEnvelope

- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (BOOL) hasSource {
  return !!hasSource_;
}
- (void) setHasSource:(BOOL) _value_ {
  hasSource_ = !!_value_;
}
@synthesize source;
- (BOOL) hasSourceDevice {
  return !!hasSourceDevice_;
}
- (void) setHasSourceDevice:(BOOL) _value_ {
  hasSourceDevice_ = !!_value_;
}
@synthesize sourceDevice;
- (BOOL) hasRelay {
  return !!hasRelay_;
}
- (void) setHasRelay:(BOOL) _value_ {
  hasRelay_ = !!_value_;
}
@synthesize relay;
- (BOOL) hasTimestamp {
  return !!hasTimestamp_;
}
- (void) setHasTimestamp:(BOOL) _value_ {
  hasTimestamp_ = !!_value_;
}
@synthesize timestamp;
- (BOOL) hasLegacyMessage {
  return !!hasLegacyMessage_;
}
- (void) setHasLegacyMessage:(BOOL) _value_ {
  hasLegacyMessage_ = !!_value_;
}
@synthesize legacyMessage;
- (BOOL) hasContent {
  return !!hasContent_;
}
- (void) setHasContent:(BOOL) _value_ {
  hasContent_ = !!_value_;
}
@synthesize content;
- (instancetype) init {
  if ((self = [super init])) {
    self.type = SSKProtoEnvelopeTypeUnknown;
    self.source = @"";
    self.sourceDevice = 0;
    self.relay = @"";
    self.timestamp = 0L;
    self.legacyMessage = [NSData data];
    self.content = [NSData data];
  }
  return self;
}
static SSKProtoEnvelope* defaultSSKProtoEnvelopeInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoEnvelope class]) {
    defaultSSKProtoEnvelopeInstance = [[SSKProtoEnvelope alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoEnvelopeInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoEnvelopeInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasType) {
    [output writeEnum:1 value:self.type];
  }
  if (self.hasSource) {
    [output writeString:2 value:self.source];
  }
  if (self.hasRelay) {
    [output writeString:3 value:self.relay];
  }
  if (self.hasTimestamp) {
    [output writeUInt64:5 value:self.timestamp];
  }
  if (self.hasLegacyMessage) {
    [output writeData:6 value:self.legacyMessage];
  }
  if (self.hasSourceDevice) {
    [output writeUInt32:7 value:self.sourceDevice];
  }
  if (self.hasContent) {
    [output writeData:8 value:self.content];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasType) {
    size_ += computeEnumSize(1, self.type);
  }
  if (self.hasSource) {
    size_ += computeStringSize(2, self.source);
  }
  if (self.hasRelay) {
    size_ += computeStringSize(3, self.relay);
  }
  if (self.hasTimestamp) {
    size_ += computeUInt64Size(5, self.timestamp);
  }
  if (self.hasLegacyMessage) {
    size_ += computeDataSize(6, self.legacyMessage);
  }
  if (self.hasSourceDevice) {
    size_ += computeUInt32Size(7, self.sourceDevice);
  }
  if (self.hasContent) {
    size_ += computeDataSize(8, self.content);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoEnvelope*) parseFromData:(NSData*) data {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromData:data] build];
}
+ (SSKProtoEnvelope*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoEnvelope*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromInputStream:input] build];
}
+ (SSKProtoEnvelope*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoEnvelope*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoEnvelope*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoEnvelope*)[[[SSKProtoEnvelope builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoEnvelopeBuilder*) builder {
  return [[SSKProtoEnvelopeBuilder alloc] init];
}
+ (SSKProtoEnvelopeBuilder*) builderWithPrototype:(SSKProtoEnvelope*) prototype {
  return [[SSKProtoEnvelope builder] mergeFrom:prototype];
}
- (SSKProtoEnvelopeBuilder*) builder {
  return [SSKProtoEnvelope builder];
}
- (SSKProtoEnvelopeBuilder*) toBuilder {
  return [SSKProtoEnvelope builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoEnvelopeType(self.type)];
  }
  if (self.hasSource) {
    [output appendFormat:@"%@%@: %@\n", indent, @"source", self.source];
  }
  if (self.hasRelay) {
    [output appendFormat:@"%@%@: %@\n", indent, @"relay", self.relay];
  }
  if (self.hasTimestamp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"timestamp", [NSNumber numberWithLongLong:self.timestamp]];
  }
  if (self.hasLegacyMessage) {
    [output appendFormat:@"%@%@: %@\n", indent, @"legacyMessage", self.legacyMessage];
  }
  if (self.hasSourceDevice) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sourceDevice", [NSNumber numberWithInteger:self.sourceDevice]];
  }
  if (self.hasContent) {
    [output appendFormat:@"%@%@: %@\n", indent, @"content", self.content];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  if (self.hasSource) {
    [dictionary setObject: self.source forKey: @"source"];
  }
  if (self.hasRelay) {
    [dictionary setObject: self.relay forKey: @"relay"];
  }
  if (self.hasTimestamp) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.timestamp] forKey: @"timestamp"];
  }
  if (self.hasLegacyMessage) {
    [dictionary setObject: self.legacyMessage forKey: @"legacyMessage"];
  }
  if (self.hasSourceDevice) {
    [dictionary setObject: [NSNumber numberWithInteger:self.sourceDevice] forKey: @"sourceDevice"];
  }
  if (self.hasContent) {
    [dictionary setObject: self.content forKey: @"content"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoEnvelope class]]) {
    return NO;
  }
  SSKProtoEnvelope *otherMessage = other;
  return
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      self.hasSource == otherMessage.hasSource &&
      (!self.hasSource || [self.source isEqual:otherMessage.source]) &&
      self.hasRelay == otherMessage.hasRelay &&
      (!self.hasRelay || [self.relay isEqual:otherMessage.relay]) &&
      self.hasTimestamp == otherMessage.hasTimestamp &&
      (!self.hasTimestamp || self.timestamp == otherMessage.timestamp) &&
      self.hasLegacyMessage == otherMessage.hasLegacyMessage &&
      (!self.hasLegacyMessage || [self.legacyMessage isEqual:otherMessage.legacyMessage]) &&
      self.hasSourceDevice == otherMessage.hasSourceDevice &&
      (!self.hasSourceDevice || self.sourceDevice == otherMessage.sourceDevice) &&
      self.hasContent == otherMessage.hasContent &&
      (!self.hasContent || [self.content isEqual:otherMessage.content]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  if (self.hasSource) {
    hashCode = hashCode * 31 + [self.source hash];
  }
  if (self.hasRelay) {
    hashCode = hashCode * 31 + [self.relay hash];
  }
  if (self.hasTimestamp) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.timestamp] hash];
  }
  if (self.hasLegacyMessage) {
    hashCode = hashCode * 31 + [self.legacyMessage hash];
  }
  if (self.hasSourceDevice) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.sourceDevice] hash];
  }
  if (self.hasContent) {
    hashCode = hashCode * 31 + [self.content hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoEnvelopeTypeIsValidValue(SSKProtoEnvelopeType value) {
  switch (value) {
    case SSKProtoEnvelopeTypeUnknown:
    case SSKProtoEnvelopeTypeCiphertext:
    case SSKProtoEnvelopeTypeKeyExchange:
    case SSKProtoEnvelopeTypePrekeyBundle:
    case SSKProtoEnvelopeTypeReceipt:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoEnvelopeType(SSKProtoEnvelopeType value) {
  switch (value) {
    case SSKProtoEnvelopeTypeUnknown:
      return @"SSKProtoEnvelopeTypeUnknown";
    case SSKProtoEnvelopeTypeCiphertext:
      return @"SSKProtoEnvelopeTypeCiphertext";
    case SSKProtoEnvelopeTypeKeyExchange:
      return @"SSKProtoEnvelopeTypeKeyExchange";
    case SSKProtoEnvelopeTypePrekeyBundle:
      return @"SSKProtoEnvelopeTypePrekeyBundle";
    case SSKProtoEnvelopeTypeReceipt:
      return @"SSKProtoEnvelopeTypeReceipt";
    default:
      return nil;
  }
}

@interface SSKProtoEnvelopeBuilder()
@property (strong) SSKProtoEnvelope* resultEnvelope;
@end

@implementation SSKProtoEnvelopeBuilder
@synthesize resultEnvelope;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultEnvelope = [[SSKProtoEnvelope alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultEnvelope;
}
- (SSKProtoEnvelopeBuilder*) clear {
  self.resultEnvelope = [[SSKProtoEnvelope alloc] init];
  return self;
}
- (SSKProtoEnvelopeBuilder*) clone {
  return [SSKProtoEnvelope builderWithPrototype:resultEnvelope];
}
- (SSKProtoEnvelope*) defaultInstance {
  return [SSKProtoEnvelope defaultInstance];
}
- (SSKProtoEnvelope*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoEnvelope*) buildPartial {
  SSKProtoEnvelope* returnMe = resultEnvelope;
  self.resultEnvelope = nil;
  return returnMe;
}
- (SSKProtoEnvelopeBuilder*) mergeFrom:(SSKProtoEnvelope*) other {
  if (other == [SSKProtoEnvelope defaultInstance]) {
    return self;
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.hasSource) {
    [self setSource:other.source];
  }
  if (other.hasSourceDevice) {
    [self setSourceDevice:other.sourceDevice];
  }
  if (other.hasRelay) {
    [self setRelay:other.relay];
  }
  if (other.hasTimestamp) {
    [self setTimestamp:other.timestamp];
  }
  if (other.hasLegacyMessage) {
    [self setLegacyMessage:other.legacyMessage];
  }
  if (other.hasContent) {
    [self setContent:other.content];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoEnvelopeBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoEnvelopeBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        SSKProtoEnvelopeType value = (SSKProtoEnvelopeType)[input readEnum];
        if (SSKProtoEnvelopeTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:1 value:value];
        }
        break;
      }
      case 18: {
        [self setSource:[input readString]];
        break;
      }
      case 26: {
        [self setRelay:[input readString]];
        break;
      }
      case 40: {
        [self setTimestamp:[input readUInt64]];
        break;
      }
      case 50: {
        [self setLegacyMessage:[input readData]];
        break;
      }
      case 56: {
        [self setSourceDevice:[input readUInt32]];
        break;
      }
      case 66: {
        [self setContent:[input readData]];
        break;
      }
    }
  }
}
- (BOOL) hasType {
  return resultEnvelope.hasType;
}
- (SSKProtoEnvelopeType) type {
  return resultEnvelope.type;
}
- (SSKProtoEnvelopeBuilder*) setType:(SSKProtoEnvelopeType) value {
  resultEnvelope.hasType = YES;
  resultEnvelope.type = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearType {
  resultEnvelope.hasType = NO;
  resultEnvelope.type = SSKProtoEnvelopeTypeUnknown;
  return self;
}
- (BOOL) hasSource {
  return resultEnvelope.hasSource;
}
- (NSString*) source {
  return resultEnvelope.source;
}
- (SSKProtoEnvelopeBuilder*) setSource:(NSString*) value {
  resultEnvelope.hasSource = YES;
  resultEnvelope.source = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearSource {
  resultEnvelope.hasSource = NO;
  resultEnvelope.source = @"";
  return self;
}
- (BOOL) hasSourceDevice {
  return resultEnvelope.hasSourceDevice;
}
- (UInt32) sourceDevice {
  return resultEnvelope.sourceDevice;
}
- (SSKProtoEnvelopeBuilder*) setSourceDevice:(UInt32) value {
  resultEnvelope.hasSourceDevice = YES;
  resultEnvelope.sourceDevice = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearSourceDevice {
  resultEnvelope.hasSourceDevice = NO;
  resultEnvelope.sourceDevice = 0;
  return self;
}
- (BOOL) hasRelay {
  return resultEnvelope.hasRelay;
}
- (NSString*) relay {
  return resultEnvelope.relay;
}
- (SSKProtoEnvelopeBuilder*) setRelay:(NSString*) value {
  resultEnvelope.hasRelay = YES;
  resultEnvelope.relay = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearRelay {
  resultEnvelope.hasRelay = NO;
  resultEnvelope.relay = @"";
  return self;
}
- (BOOL) hasTimestamp {
  return resultEnvelope.hasTimestamp;
}
- (UInt64) timestamp {
  return resultEnvelope.timestamp;
}
- (SSKProtoEnvelopeBuilder*) setTimestamp:(UInt64) value {
  resultEnvelope.hasTimestamp = YES;
  resultEnvelope.timestamp = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearTimestamp {
  resultEnvelope.hasTimestamp = NO;
  resultEnvelope.timestamp = 0L;
  return self;
}
- (BOOL) hasLegacyMessage {
  return resultEnvelope.hasLegacyMessage;
}
- (NSData*) legacyMessage {
  return resultEnvelope.legacyMessage;
}
- (SSKProtoEnvelopeBuilder*) setLegacyMessage:(NSData*) value {
  resultEnvelope.hasLegacyMessage = YES;
  resultEnvelope.legacyMessage = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearLegacyMessage {
  resultEnvelope.hasLegacyMessage = NO;
  resultEnvelope.legacyMessage = [NSData data];
  return self;
}
- (BOOL) hasContent {
  return resultEnvelope.hasContent;
}
- (NSData*) content {
  return resultEnvelope.content;
}
- (SSKProtoEnvelopeBuilder*) setContent:(NSData*) value {
  resultEnvelope.hasContent = YES;
  resultEnvelope.content = value;
  return self;
}
- (SSKProtoEnvelopeBuilder*) clearContent {
  resultEnvelope.hasContent = NO;
  resultEnvelope.content = [NSData data];
  return self;
}
@end

@interface SSKProtoContent ()
@property (strong) SSKProtoDataMessage* dataMessage;
@property (strong) SSKProtoSyncMessage* syncMessage;
@property (strong) SSKProtoCallMessage* callMessage;
@property (strong) SSKProtoNullMessage* nullMessage;
@property (strong) SSKProtoReceiptMessage* receiptMessage;
@end

@implementation SSKProtoContent

- (BOOL) hasDataMessage {
  return !!hasDataMessage_;
}
- (void) setHasDataMessage:(BOOL) _value_ {
  hasDataMessage_ = !!_value_;
}
@synthesize dataMessage;
- (BOOL) hasSyncMessage {
  return !!hasSyncMessage_;
}
- (void) setHasSyncMessage:(BOOL) _value_ {
  hasSyncMessage_ = !!_value_;
}
@synthesize syncMessage;
- (BOOL) hasCallMessage {
  return !!hasCallMessage_;
}
- (void) setHasCallMessage:(BOOL) _value_ {
  hasCallMessage_ = !!_value_;
}
@synthesize callMessage;
- (BOOL) hasNullMessage {
  return !!hasNullMessage_;
}
- (void) setHasNullMessage:(BOOL) _value_ {
  hasNullMessage_ = !!_value_;
}
@synthesize nullMessage;
- (BOOL) hasReceiptMessage {
  return !!hasReceiptMessage_;
}
- (void) setHasReceiptMessage:(BOOL) _value_ {
  hasReceiptMessage_ = !!_value_;
}
@synthesize receiptMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.dataMessage = [SSKProtoDataMessage defaultInstance];
    self.syncMessage = [SSKProtoSyncMessage defaultInstance];
    self.callMessage = [SSKProtoCallMessage defaultInstance];
    self.nullMessage = [SSKProtoNullMessage defaultInstance];
    self.receiptMessage = [SSKProtoReceiptMessage defaultInstance];
  }
  return self;
}
static SSKProtoContent* defaultSSKProtoContentInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoContent class]) {
    defaultSSKProtoContentInstance = [[SSKProtoContent alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoContentInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoContentInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasDataMessage) {
    [output writeMessage:1 value:self.dataMessage];
  }
  if (self.hasSyncMessage) {
    [output writeMessage:2 value:self.syncMessage];
  }
  if (self.hasCallMessage) {
    [output writeMessage:3 value:self.callMessage];
  }
  if (self.hasNullMessage) {
    [output writeMessage:4 value:self.nullMessage];
  }
  if (self.hasReceiptMessage) {
    [output writeMessage:5 value:self.receiptMessage];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasDataMessage) {
    size_ += computeMessageSize(1, self.dataMessage);
  }
  if (self.hasSyncMessage) {
    size_ += computeMessageSize(2, self.syncMessage);
  }
  if (self.hasCallMessage) {
    size_ += computeMessageSize(3, self.callMessage);
  }
  if (self.hasNullMessage) {
    size_ += computeMessageSize(4, self.nullMessage);
  }
  if (self.hasReceiptMessage) {
    size_ += computeMessageSize(5, self.receiptMessage);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoContent*) parseFromData:(NSData*) data {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromData:data] build];
}
+ (SSKProtoContent*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContent*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromInputStream:input] build];
}
+ (SSKProtoContent*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContent*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoContent*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContent*)[[[SSKProtoContent builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContentBuilder*) builder {
  return [[SSKProtoContentBuilder alloc] init];
}
+ (SSKProtoContentBuilder*) builderWithPrototype:(SSKProtoContent*) prototype {
  return [[SSKProtoContent builder] mergeFrom:prototype];
}
- (SSKProtoContentBuilder*) builder {
  return [SSKProtoContent builder];
}
- (SSKProtoContentBuilder*) toBuilder {
  return [SSKProtoContent builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasDataMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"dataMessage"];
    [self.dataMessage writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasSyncMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"syncMessage"];
    [self.syncMessage writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasCallMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"callMessage"];
    [self.callMessage writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasNullMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"nullMessage"];
    [self.nullMessage writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasReceiptMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"receiptMessage"];
    [self.receiptMessage writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasDataMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.dataMessage storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"dataMessage"];
  }
  if (self.hasSyncMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.syncMessage storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"syncMessage"];
  }
  if (self.hasCallMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.callMessage storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"callMessage"];
  }
  if (self.hasNullMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.nullMessage storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"nullMessage"];
  }
  if (self.hasReceiptMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.receiptMessage storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"receiptMessage"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoContent class]]) {
    return NO;
  }
  SSKProtoContent *otherMessage = other;
  return
      self.hasDataMessage == otherMessage.hasDataMessage &&
      (!self.hasDataMessage || [self.dataMessage isEqual:otherMessage.dataMessage]) &&
      self.hasSyncMessage == otherMessage.hasSyncMessage &&
      (!self.hasSyncMessage || [self.syncMessage isEqual:otherMessage.syncMessage]) &&
      self.hasCallMessage == otherMessage.hasCallMessage &&
      (!self.hasCallMessage || [self.callMessage isEqual:otherMessage.callMessage]) &&
      self.hasNullMessage == otherMessage.hasNullMessage &&
      (!self.hasNullMessage || [self.nullMessage isEqual:otherMessage.nullMessage]) &&
      self.hasReceiptMessage == otherMessage.hasReceiptMessage &&
      (!self.hasReceiptMessage || [self.receiptMessage isEqual:otherMessage.receiptMessage]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasDataMessage) {
    hashCode = hashCode * 31 + [self.dataMessage hash];
  }
  if (self.hasSyncMessage) {
    hashCode = hashCode * 31 + [self.syncMessage hash];
  }
  if (self.hasCallMessage) {
    hashCode = hashCode * 31 + [self.callMessage hash];
  }
  if (self.hasNullMessage) {
    hashCode = hashCode * 31 + [self.nullMessage hash];
  }
  if (self.hasReceiptMessage) {
    hashCode = hashCode * 31 + [self.receiptMessage hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoContentBuilder()
@property (strong) SSKProtoContent* resultContent;
@end

@implementation SSKProtoContentBuilder
@synthesize resultContent;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultContent = [[SSKProtoContent alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultContent;
}
- (SSKProtoContentBuilder*) clear {
  self.resultContent = [[SSKProtoContent alloc] init];
  return self;
}
- (SSKProtoContentBuilder*) clone {
  return [SSKProtoContent builderWithPrototype:resultContent];
}
- (SSKProtoContent*) defaultInstance {
  return [SSKProtoContent defaultInstance];
}
- (SSKProtoContent*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoContent*) buildPartial {
  SSKProtoContent* returnMe = resultContent;
  self.resultContent = nil;
  return returnMe;
}
- (SSKProtoContentBuilder*) mergeFrom:(SSKProtoContent*) other {
  if (other == [SSKProtoContent defaultInstance]) {
    return self;
  }
  if (other.hasDataMessage) {
    [self mergeDataMessage:other.dataMessage];
  }
  if (other.hasSyncMessage) {
    [self mergeSyncMessage:other.syncMessage];
  }
  if (other.hasCallMessage) {
    [self mergeCallMessage:other.callMessage];
  }
  if (other.hasNullMessage) {
    [self mergeNullMessage:other.nullMessage];
  }
  if (other.hasReceiptMessage) {
    [self mergeReceiptMessage:other.receiptMessage];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoContentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoContentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoDataMessageBuilder* subBuilder = [SSKProtoDataMessage builder];
        if (self.hasDataMessage) {
          [subBuilder mergeFrom:self.dataMessage];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setDataMessage:[subBuilder buildPartial]];
        break;
      }
      case 18: {
        SSKProtoSyncMessageBuilder* subBuilder = [SSKProtoSyncMessage builder];
        if (self.hasSyncMessage) {
          [subBuilder mergeFrom:self.syncMessage];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setSyncMessage:[subBuilder buildPartial]];
        break;
      }
      case 26: {
        SSKProtoCallMessageBuilder* subBuilder = [SSKProtoCallMessage builder];
        if (self.hasCallMessage) {
          [subBuilder mergeFrom:self.callMessage];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setCallMessage:[subBuilder buildPartial]];
        break;
      }
      case 34: {
        SSKProtoNullMessageBuilder* subBuilder = [SSKProtoNullMessage builder];
        if (self.hasNullMessage) {
          [subBuilder mergeFrom:self.nullMessage];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setNullMessage:[subBuilder buildPartial]];
        break;
      }
      case 42: {
        SSKProtoReceiptMessageBuilder* subBuilder = [SSKProtoReceiptMessage builder];
        if (self.hasReceiptMessage) {
          [subBuilder mergeFrom:self.receiptMessage];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setReceiptMessage:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasDataMessage {
  return resultContent.hasDataMessage;
}
- (SSKProtoDataMessage*) dataMessage {
  return resultContent.dataMessage;
}
- (SSKProtoContentBuilder*) setDataMessage:(SSKProtoDataMessage*) value {
  resultContent.hasDataMessage = YES;
  resultContent.dataMessage = value;
  return self;
}
- (SSKProtoContentBuilder*) setDataMessageBuilder:(SSKProtoDataMessageBuilder*) builderForValue {
  return [self setDataMessage:[builderForValue build]];
}
- (SSKProtoContentBuilder*) mergeDataMessage:(SSKProtoDataMessage*) value {
  if (resultContent.hasDataMessage &&
      resultContent.dataMessage != [SSKProtoDataMessage defaultInstance]) {
    resultContent.dataMessage =
      [[[SSKProtoDataMessage builderWithPrototype:resultContent.dataMessage] mergeFrom:value] buildPartial];
  } else {
    resultContent.dataMessage = value;
  }
  resultContent.hasDataMessage = YES;
  return self;
}
- (SSKProtoContentBuilder*) clearDataMessage {
  resultContent.hasDataMessage = NO;
  resultContent.dataMessage = [SSKProtoDataMessage defaultInstance];
  return self;
}
- (BOOL) hasSyncMessage {
  return resultContent.hasSyncMessage;
}
- (SSKProtoSyncMessage*) syncMessage {
  return resultContent.syncMessage;
}
- (SSKProtoContentBuilder*) setSyncMessage:(SSKProtoSyncMessage*) value {
  resultContent.hasSyncMessage = YES;
  resultContent.syncMessage = value;
  return self;
}
- (SSKProtoContentBuilder*) setSyncMessageBuilder:(SSKProtoSyncMessageBuilder*) builderForValue {
  return [self setSyncMessage:[builderForValue build]];
}
- (SSKProtoContentBuilder*) mergeSyncMessage:(SSKProtoSyncMessage*) value {
  if (resultContent.hasSyncMessage &&
      resultContent.syncMessage != [SSKProtoSyncMessage defaultInstance]) {
    resultContent.syncMessage =
      [[[SSKProtoSyncMessage builderWithPrototype:resultContent.syncMessage] mergeFrom:value] buildPartial];
  } else {
    resultContent.syncMessage = value;
  }
  resultContent.hasSyncMessage = YES;
  return self;
}
- (SSKProtoContentBuilder*) clearSyncMessage {
  resultContent.hasSyncMessage = NO;
  resultContent.syncMessage = [SSKProtoSyncMessage defaultInstance];
  return self;
}
- (BOOL) hasCallMessage {
  return resultContent.hasCallMessage;
}
- (SSKProtoCallMessage*) callMessage {
  return resultContent.callMessage;
}
- (SSKProtoContentBuilder*) setCallMessage:(SSKProtoCallMessage*) value {
  resultContent.hasCallMessage = YES;
  resultContent.callMessage = value;
  return self;
}
- (SSKProtoContentBuilder*) setCallMessageBuilder:(SSKProtoCallMessageBuilder*) builderForValue {
  return [self setCallMessage:[builderForValue build]];
}
- (SSKProtoContentBuilder*) mergeCallMessage:(SSKProtoCallMessage*) value {
  if (resultContent.hasCallMessage &&
      resultContent.callMessage != [SSKProtoCallMessage defaultInstance]) {
    resultContent.callMessage =
      [[[SSKProtoCallMessage builderWithPrototype:resultContent.callMessage] mergeFrom:value] buildPartial];
  } else {
    resultContent.callMessage = value;
  }
  resultContent.hasCallMessage = YES;
  return self;
}
- (SSKProtoContentBuilder*) clearCallMessage {
  resultContent.hasCallMessage = NO;
  resultContent.callMessage = [SSKProtoCallMessage defaultInstance];
  return self;
}
- (BOOL) hasNullMessage {
  return resultContent.hasNullMessage;
}
- (SSKProtoNullMessage*) nullMessage {
  return resultContent.nullMessage;
}
- (SSKProtoContentBuilder*) setNullMessage:(SSKProtoNullMessage*) value {
  resultContent.hasNullMessage = YES;
  resultContent.nullMessage = value;
  return self;
}
- (SSKProtoContentBuilder*) setNullMessageBuilder:(SSKProtoNullMessageBuilder*) builderForValue {
  return [self setNullMessage:[builderForValue build]];
}
- (SSKProtoContentBuilder*) mergeNullMessage:(SSKProtoNullMessage*) value {
  if (resultContent.hasNullMessage &&
      resultContent.nullMessage != [SSKProtoNullMessage defaultInstance]) {
    resultContent.nullMessage =
      [[[SSKProtoNullMessage builderWithPrototype:resultContent.nullMessage] mergeFrom:value] buildPartial];
  } else {
    resultContent.nullMessage = value;
  }
  resultContent.hasNullMessage = YES;
  return self;
}
- (SSKProtoContentBuilder*) clearNullMessage {
  resultContent.hasNullMessage = NO;
  resultContent.nullMessage = [SSKProtoNullMessage defaultInstance];
  return self;
}
- (BOOL) hasReceiptMessage {
  return resultContent.hasReceiptMessage;
}
- (SSKProtoReceiptMessage*) receiptMessage {
  return resultContent.receiptMessage;
}
- (SSKProtoContentBuilder*) setReceiptMessage:(SSKProtoReceiptMessage*) value {
  resultContent.hasReceiptMessage = YES;
  resultContent.receiptMessage = value;
  return self;
}
- (SSKProtoContentBuilder*) setReceiptMessageBuilder:(SSKProtoReceiptMessageBuilder*) builderForValue {
  return [self setReceiptMessage:[builderForValue build]];
}
- (SSKProtoContentBuilder*) mergeReceiptMessage:(SSKProtoReceiptMessage*) value {
  if (resultContent.hasReceiptMessage &&
      resultContent.receiptMessage != [SSKProtoReceiptMessage defaultInstance]) {
    resultContent.receiptMessage =
      [[[SSKProtoReceiptMessage builderWithPrototype:resultContent.receiptMessage] mergeFrom:value] buildPartial];
  } else {
    resultContent.receiptMessage = value;
  }
  resultContent.hasReceiptMessage = YES;
  return self;
}
- (SSKProtoContentBuilder*) clearReceiptMessage {
  resultContent.hasReceiptMessage = NO;
  resultContent.receiptMessage = [SSKProtoReceiptMessage defaultInstance];
  return self;
}
@end

@interface SSKProtoCallMessage ()
@property (strong) SSKProtoCallMessageOffer* offer;
@property (strong) SSKProtoCallMessageAnswer* answer;
@property (strong) NSMutableArray<SSKProtoCallMessageIceUpdate*> * iceUpdateArray;
@property (strong) SSKProtoCallMessageHangup* hangup;
@property (strong) SSKProtoCallMessageBusy* busy;
@property (strong) NSData* profileKey;
@end

@implementation SSKProtoCallMessage

- (BOOL) hasOffer {
  return !!hasOffer_;
}
- (void) setHasOffer:(BOOL) _value_ {
  hasOffer_ = !!_value_;
}
@synthesize offer;
- (BOOL) hasAnswer {
  return !!hasAnswer_;
}
- (void) setHasAnswer:(BOOL) _value_ {
  hasAnswer_ = !!_value_;
}
@synthesize answer;
@synthesize iceUpdateArray;
@dynamic iceUpdate;
- (BOOL) hasHangup {
  return !!hasHangup_;
}
- (void) setHasHangup:(BOOL) _value_ {
  hasHangup_ = !!_value_;
}
@synthesize hangup;
- (BOOL) hasBusy {
  return !!hasBusy_;
}
- (void) setHasBusy:(BOOL) _value_ {
  hasBusy_ = !!_value_;
}
@synthesize busy;
- (BOOL) hasProfileKey {
  return !!hasProfileKey_;
}
- (void) setHasProfileKey:(BOOL) _value_ {
  hasProfileKey_ = !!_value_;
}
@synthesize profileKey;
- (instancetype) init {
  if ((self = [super init])) {
    self.offer = [SSKProtoCallMessageOffer defaultInstance];
    self.answer = [SSKProtoCallMessageAnswer defaultInstance];
    self.hangup = [SSKProtoCallMessageHangup defaultInstance];
    self.busy = [SSKProtoCallMessageBusy defaultInstance];
    self.profileKey = [NSData data];
  }
  return self;
}
static SSKProtoCallMessage* defaultSSKProtoCallMessageInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessage class]) {
    defaultSSKProtoCallMessageInstance = [[SSKProtoCallMessage alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageInstance;
}
- (NSArray<SSKProtoCallMessageIceUpdate*> *)iceUpdate {
  return iceUpdateArray;
}
- (SSKProtoCallMessageIceUpdate*)iceUpdateAtIndex:(NSUInteger)index {
  return [iceUpdateArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasOffer) {
    [output writeMessage:1 value:self.offer];
  }
  if (self.hasAnswer) {
    [output writeMessage:2 value:self.answer];
  }
  [self.iceUpdateArray enumerateObjectsUsingBlock:^(SSKProtoCallMessageIceUpdate *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:3 value:element];
  }];
  if (self.hasHangup) {
    [output writeMessage:4 value:self.hangup];
  }
  if (self.hasBusy) {
    [output writeMessage:5 value:self.busy];
  }
  if (self.hasProfileKey) {
    [output writeData:6 value:self.profileKey];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasOffer) {
    size_ += computeMessageSize(1, self.offer);
  }
  if (self.hasAnswer) {
    size_ += computeMessageSize(2, self.answer);
  }
  [self.iceUpdateArray enumerateObjectsUsingBlock:^(SSKProtoCallMessageIceUpdate *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(3, element);
  }];
  if (self.hasHangup) {
    size_ += computeMessageSize(4, self.hangup);
  }
  if (self.hasBusy) {
    size_ += computeMessageSize(5, self.busy);
  }
  if (self.hasProfileKey) {
    size_ += computeDataSize(6, self.profileKey);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessage*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessage*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessage*)[[[SSKProtoCallMessage builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageBuilder*) builder {
  return [[SSKProtoCallMessageBuilder alloc] init];
}
+ (SSKProtoCallMessageBuilder*) builderWithPrototype:(SSKProtoCallMessage*) prototype {
  return [[SSKProtoCallMessage builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageBuilder*) builder {
  return [SSKProtoCallMessage builder];
}
- (SSKProtoCallMessageBuilder*) toBuilder {
  return [SSKProtoCallMessage builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasOffer) {
    [output appendFormat:@"%@%@ {\n", indent, @"offer"];
    [self.offer writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasAnswer) {
    [output appendFormat:@"%@%@ {\n", indent, @"answer"];
    [self.answer writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.iceUpdateArray enumerateObjectsUsingBlock:^(SSKProtoCallMessageIceUpdate *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"iceUpdate"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  if (self.hasHangup) {
    [output appendFormat:@"%@%@ {\n", indent, @"hangup"];
    [self.hangup writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasBusy) {
    [output appendFormat:@"%@%@ {\n", indent, @"busy"];
    [self.busy writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasProfileKey) {
    [output appendFormat:@"%@%@: %@\n", indent, @"profileKey", self.profileKey];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasOffer) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.offer storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"offer"];
  }
  if (self.hasAnswer) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.answer storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"answer"];
  }
  for (SSKProtoCallMessageIceUpdate* element in self.iceUpdateArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"iceUpdate"];
  }
  if (self.hasHangup) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.hangup storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"hangup"];
  }
  if (self.hasBusy) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.busy storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"busy"];
  }
  if (self.hasProfileKey) {
    [dictionary setObject: self.profileKey forKey: @"profileKey"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessage class]]) {
    return NO;
  }
  SSKProtoCallMessage *otherMessage = other;
  return
      self.hasOffer == otherMessage.hasOffer &&
      (!self.hasOffer || [self.offer isEqual:otherMessage.offer]) &&
      self.hasAnswer == otherMessage.hasAnswer &&
      (!self.hasAnswer || [self.answer isEqual:otherMessage.answer]) &&
      [self.iceUpdateArray isEqualToArray:otherMessage.iceUpdateArray] &&
      self.hasHangup == otherMessage.hasHangup &&
      (!self.hasHangup || [self.hangup isEqual:otherMessage.hangup]) &&
      self.hasBusy == otherMessage.hasBusy &&
      (!self.hasBusy || [self.busy isEqual:otherMessage.busy]) &&
      self.hasProfileKey == otherMessage.hasProfileKey &&
      (!self.hasProfileKey || [self.profileKey isEqual:otherMessage.profileKey]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasOffer) {
    hashCode = hashCode * 31 + [self.offer hash];
  }
  if (self.hasAnswer) {
    hashCode = hashCode * 31 + [self.answer hash];
  }
  [self.iceUpdateArray enumerateObjectsUsingBlock:^(SSKProtoCallMessageIceUpdate *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasHangup) {
    hashCode = hashCode * 31 + [self.hangup hash];
  }
  if (self.hasBusy) {
    hashCode = hashCode * 31 + [self.busy hash];
  }
  if (self.hasProfileKey) {
    hashCode = hashCode * 31 + [self.profileKey hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageOffer ()
@property UInt64 id;
@property (strong) NSString* sessionDescription;
@end

@implementation SSKProtoCallMessageOffer

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasSessionDescription {
  return !!hasSessionDescription_;
}
- (void) setHasSessionDescription:(BOOL) _value_ {
  hasSessionDescription_ = !!_value_;
}
@synthesize sessionDescription;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
    self.sessionDescription = @"";
  }
  return self;
}
static SSKProtoCallMessageOffer* defaultSSKProtoCallMessageOfferInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessageOffer class]) {
    defaultSSKProtoCallMessageOfferInstance = [[SSKProtoCallMessageOffer alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageOfferInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageOfferInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  if (self.hasSessionDescription) {
    [output writeString:2 value:self.sessionDescription];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  if (self.hasSessionDescription) {
    size_ += computeStringSize(2, self.sessionDescription);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessageOffer*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessageOffer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageOffer*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessageOffer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageOffer*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessageOffer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageOffer*)[[[SSKProtoCallMessageOffer builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageOfferBuilder*) builder {
  return [[SSKProtoCallMessageOfferBuilder alloc] init];
}
+ (SSKProtoCallMessageOfferBuilder*) builderWithPrototype:(SSKProtoCallMessageOffer*) prototype {
  return [[SSKProtoCallMessageOffer builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageOfferBuilder*) builder {
  return [SSKProtoCallMessageOffer builder];
}
- (SSKProtoCallMessageOfferBuilder*) toBuilder {
  return [SSKProtoCallMessageOffer builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  if (self.hasSessionDescription) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sessionDescription", self.sessionDescription];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  if (self.hasSessionDescription) {
    [dictionary setObject: self.sessionDescription forKey: @"sessionDescription"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessageOffer class]]) {
    return NO;
  }
  SSKProtoCallMessageOffer *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      self.hasSessionDescription == otherMessage.hasSessionDescription &&
      (!self.hasSessionDescription || [self.sessionDescription isEqual:otherMessage.sessionDescription]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  if (self.hasSessionDescription) {
    hashCode = hashCode * 31 + [self.sessionDescription hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageOfferBuilder()
@property (strong) SSKProtoCallMessageOffer* resultOffer;
@end

@implementation SSKProtoCallMessageOfferBuilder
@synthesize resultOffer;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultOffer = [[SSKProtoCallMessageOffer alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultOffer;
}
- (SSKProtoCallMessageOfferBuilder*) clear {
  self.resultOffer = [[SSKProtoCallMessageOffer alloc] init];
  return self;
}
- (SSKProtoCallMessageOfferBuilder*) clone {
  return [SSKProtoCallMessageOffer builderWithPrototype:resultOffer];
}
- (SSKProtoCallMessageOffer*) defaultInstance {
  return [SSKProtoCallMessageOffer defaultInstance];
}
- (SSKProtoCallMessageOffer*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessageOffer*) buildPartial {
  SSKProtoCallMessageOffer* returnMe = resultOffer;
  self.resultOffer = nil;
  return returnMe;
}
- (SSKProtoCallMessageOfferBuilder*) mergeFrom:(SSKProtoCallMessageOffer*) other {
  if (other == [SSKProtoCallMessageOffer defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasSessionDescription) {
    [self setSessionDescription:other.sessionDescription];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageOfferBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageOfferBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
      case 18: {
        [self setSessionDescription:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultOffer.hasId;
}
- (UInt64) id {
  return resultOffer.id;
}
- (SSKProtoCallMessageOfferBuilder*) setId:(UInt64) value {
  resultOffer.hasId = YES;
  resultOffer.id = value;
  return self;
}
- (SSKProtoCallMessageOfferBuilder*) clearId {
  resultOffer.hasId = NO;
  resultOffer.id = 0L;
  return self;
}
- (BOOL) hasSessionDescription {
  return resultOffer.hasSessionDescription;
}
- (NSString*) sessionDescription {
  return resultOffer.sessionDescription;
}
- (SSKProtoCallMessageOfferBuilder*) setSessionDescription:(NSString*) value {
  resultOffer.hasSessionDescription = YES;
  resultOffer.sessionDescription = value;
  return self;
}
- (SSKProtoCallMessageOfferBuilder*) clearSessionDescription {
  resultOffer.hasSessionDescription = NO;
  resultOffer.sessionDescription = @"";
  return self;
}
@end

@interface SSKProtoCallMessageAnswer ()
@property UInt64 id;
@property (strong) NSString* sessionDescription;
@end

@implementation SSKProtoCallMessageAnswer

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasSessionDescription {
  return !!hasSessionDescription_;
}
- (void) setHasSessionDescription:(BOOL) _value_ {
  hasSessionDescription_ = !!_value_;
}
@synthesize sessionDescription;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
    self.sessionDescription = @"";
  }
  return self;
}
static SSKProtoCallMessageAnswer* defaultSSKProtoCallMessageAnswerInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessageAnswer class]) {
    defaultSSKProtoCallMessageAnswerInstance = [[SSKProtoCallMessageAnswer alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageAnswerInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageAnswerInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  if (self.hasSessionDescription) {
    [output writeString:2 value:self.sessionDescription];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  if (self.hasSessionDescription) {
    size_ += computeStringSize(2, self.sessionDescription);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessageAnswer*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessageAnswer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageAnswer*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessageAnswer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageAnswer*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessageAnswer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageAnswer*)[[[SSKProtoCallMessageAnswer builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageAnswerBuilder*) builder {
  return [[SSKProtoCallMessageAnswerBuilder alloc] init];
}
+ (SSKProtoCallMessageAnswerBuilder*) builderWithPrototype:(SSKProtoCallMessageAnswer*) prototype {
  return [[SSKProtoCallMessageAnswer builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageAnswerBuilder*) builder {
  return [SSKProtoCallMessageAnswer builder];
}
- (SSKProtoCallMessageAnswerBuilder*) toBuilder {
  return [SSKProtoCallMessageAnswer builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  if (self.hasSessionDescription) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sessionDescription", self.sessionDescription];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  if (self.hasSessionDescription) {
    [dictionary setObject: self.sessionDescription forKey: @"sessionDescription"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessageAnswer class]]) {
    return NO;
  }
  SSKProtoCallMessageAnswer *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      self.hasSessionDescription == otherMessage.hasSessionDescription &&
      (!self.hasSessionDescription || [self.sessionDescription isEqual:otherMessage.sessionDescription]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  if (self.hasSessionDescription) {
    hashCode = hashCode * 31 + [self.sessionDescription hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageAnswerBuilder()
@property (strong) SSKProtoCallMessageAnswer* resultAnswer;
@end

@implementation SSKProtoCallMessageAnswerBuilder
@synthesize resultAnswer;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultAnswer = [[SSKProtoCallMessageAnswer alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultAnswer;
}
- (SSKProtoCallMessageAnswerBuilder*) clear {
  self.resultAnswer = [[SSKProtoCallMessageAnswer alloc] init];
  return self;
}
- (SSKProtoCallMessageAnswerBuilder*) clone {
  return [SSKProtoCallMessageAnswer builderWithPrototype:resultAnswer];
}
- (SSKProtoCallMessageAnswer*) defaultInstance {
  return [SSKProtoCallMessageAnswer defaultInstance];
}
- (SSKProtoCallMessageAnswer*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessageAnswer*) buildPartial {
  SSKProtoCallMessageAnswer* returnMe = resultAnswer;
  self.resultAnswer = nil;
  return returnMe;
}
- (SSKProtoCallMessageAnswerBuilder*) mergeFrom:(SSKProtoCallMessageAnswer*) other {
  if (other == [SSKProtoCallMessageAnswer defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasSessionDescription) {
    [self setSessionDescription:other.sessionDescription];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageAnswerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageAnswerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
      case 18: {
        [self setSessionDescription:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultAnswer.hasId;
}
- (UInt64) id {
  return resultAnswer.id;
}
- (SSKProtoCallMessageAnswerBuilder*) setId:(UInt64) value {
  resultAnswer.hasId = YES;
  resultAnswer.id = value;
  return self;
}
- (SSKProtoCallMessageAnswerBuilder*) clearId {
  resultAnswer.hasId = NO;
  resultAnswer.id = 0L;
  return self;
}
- (BOOL) hasSessionDescription {
  return resultAnswer.hasSessionDescription;
}
- (NSString*) sessionDescription {
  return resultAnswer.sessionDescription;
}
- (SSKProtoCallMessageAnswerBuilder*) setSessionDescription:(NSString*) value {
  resultAnswer.hasSessionDescription = YES;
  resultAnswer.sessionDescription = value;
  return self;
}
- (SSKProtoCallMessageAnswerBuilder*) clearSessionDescription {
  resultAnswer.hasSessionDescription = NO;
  resultAnswer.sessionDescription = @"";
  return self;
}
@end

@interface SSKProtoCallMessageIceUpdate ()
@property UInt64 id;
@property (strong) NSString* sdpMid;
@property UInt32 sdpMlineIndex;
@property (strong) NSString* sdp;
@end

@implementation SSKProtoCallMessageIceUpdate

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasSdpMid {
  return !!hasSdpMid_;
}
- (void) setHasSdpMid:(BOOL) _value_ {
  hasSdpMid_ = !!_value_;
}
@synthesize sdpMid;
- (BOOL) hasSdpMlineIndex {
  return !!hasSdpMlineIndex_;
}
- (void) setHasSdpMlineIndex:(BOOL) _value_ {
  hasSdpMlineIndex_ = !!_value_;
}
@synthesize sdpMlineIndex;
- (BOOL) hasSdp {
  return !!hasSdp_;
}
- (void) setHasSdp:(BOOL) _value_ {
  hasSdp_ = !!_value_;
}
@synthesize sdp;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
    self.sdpMid = @"";
    self.sdpMlineIndex = 0;
    self.sdp = @"";
  }
  return self;
}
static SSKProtoCallMessageIceUpdate* defaultSSKProtoCallMessageIceUpdateInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessageIceUpdate class]) {
    defaultSSKProtoCallMessageIceUpdateInstance = [[SSKProtoCallMessageIceUpdate alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageIceUpdateInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageIceUpdateInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  if (self.hasSdpMid) {
    [output writeString:2 value:self.sdpMid];
  }
  if (self.hasSdpMlineIndex) {
    [output writeUInt32:3 value:self.sdpMlineIndex];
  }
  if (self.hasSdp) {
    [output writeString:4 value:self.sdp];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  if (self.hasSdpMid) {
    size_ += computeStringSize(2, self.sdpMid);
  }
  if (self.hasSdpMlineIndex) {
    size_ += computeUInt32Size(3, self.sdpMlineIndex);
  }
  if (self.hasSdp) {
    size_ += computeStringSize(4, self.sdp);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessageIceUpdate*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessageIceUpdate*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageIceUpdate*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessageIceUpdate*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageIceUpdate*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessageIceUpdate*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageIceUpdate*)[[[SSKProtoCallMessageIceUpdate builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageIceUpdateBuilder*) builder {
  return [[SSKProtoCallMessageIceUpdateBuilder alloc] init];
}
+ (SSKProtoCallMessageIceUpdateBuilder*) builderWithPrototype:(SSKProtoCallMessageIceUpdate*) prototype {
  return [[SSKProtoCallMessageIceUpdate builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageIceUpdateBuilder*) builder {
  return [SSKProtoCallMessageIceUpdate builder];
}
- (SSKProtoCallMessageIceUpdateBuilder*) toBuilder {
  return [SSKProtoCallMessageIceUpdate builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  if (self.hasSdpMid) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sdpMid", self.sdpMid];
  }
  if (self.hasSdpMlineIndex) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sdpMlineIndex", [NSNumber numberWithInteger:self.sdpMlineIndex]];
  }
  if (self.hasSdp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sdp", self.sdp];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  if (self.hasSdpMid) {
    [dictionary setObject: self.sdpMid forKey: @"sdpMid"];
  }
  if (self.hasSdpMlineIndex) {
    [dictionary setObject: [NSNumber numberWithInteger:self.sdpMlineIndex] forKey: @"sdpMlineIndex"];
  }
  if (self.hasSdp) {
    [dictionary setObject: self.sdp forKey: @"sdp"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessageIceUpdate class]]) {
    return NO;
  }
  SSKProtoCallMessageIceUpdate *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      self.hasSdpMid == otherMessage.hasSdpMid &&
      (!self.hasSdpMid || [self.sdpMid isEqual:otherMessage.sdpMid]) &&
      self.hasSdpMlineIndex == otherMessage.hasSdpMlineIndex &&
      (!self.hasSdpMlineIndex || self.sdpMlineIndex == otherMessage.sdpMlineIndex) &&
      self.hasSdp == otherMessage.hasSdp &&
      (!self.hasSdp || [self.sdp isEqual:otherMessage.sdp]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  if (self.hasSdpMid) {
    hashCode = hashCode * 31 + [self.sdpMid hash];
  }
  if (self.hasSdpMlineIndex) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.sdpMlineIndex] hash];
  }
  if (self.hasSdp) {
    hashCode = hashCode * 31 + [self.sdp hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageIceUpdateBuilder()
@property (strong) SSKProtoCallMessageIceUpdate* resultIceUpdate;
@end

@implementation SSKProtoCallMessageIceUpdateBuilder
@synthesize resultIceUpdate;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultIceUpdate = [[SSKProtoCallMessageIceUpdate alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultIceUpdate;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clear {
  self.resultIceUpdate = [[SSKProtoCallMessageIceUpdate alloc] init];
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clone {
  return [SSKProtoCallMessageIceUpdate builderWithPrototype:resultIceUpdate];
}
- (SSKProtoCallMessageIceUpdate*) defaultInstance {
  return [SSKProtoCallMessageIceUpdate defaultInstance];
}
- (SSKProtoCallMessageIceUpdate*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessageIceUpdate*) buildPartial {
  SSKProtoCallMessageIceUpdate* returnMe = resultIceUpdate;
  self.resultIceUpdate = nil;
  return returnMe;
}
- (SSKProtoCallMessageIceUpdateBuilder*) mergeFrom:(SSKProtoCallMessageIceUpdate*) other {
  if (other == [SSKProtoCallMessageIceUpdate defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasSdpMid) {
    [self setSdpMid:other.sdpMid];
  }
  if (other.hasSdpMlineIndex) {
    [self setSdpMlineIndex:other.sdpMlineIndex];
  }
  if (other.hasSdp) {
    [self setSdp:other.sdp];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageIceUpdateBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
      case 18: {
        [self setSdpMid:[input readString]];
        break;
      }
      case 24: {
        [self setSdpMlineIndex:[input readUInt32]];
        break;
      }
      case 34: {
        [self setSdp:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultIceUpdate.hasId;
}
- (UInt64) id {
  return resultIceUpdate.id;
}
- (SSKProtoCallMessageIceUpdateBuilder*) setId:(UInt64) value {
  resultIceUpdate.hasId = YES;
  resultIceUpdate.id = value;
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clearId {
  resultIceUpdate.hasId = NO;
  resultIceUpdate.id = 0L;
  return self;
}
- (BOOL) hasSdpMid {
  return resultIceUpdate.hasSdpMid;
}
- (NSString*) sdpMid {
  return resultIceUpdate.sdpMid;
}
- (SSKProtoCallMessageIceUpdateBuilder*) setSdpMid:(NSString*) value {
  resultIceUpdate.hasSdpMid = YES;
  resultIceUpdate.sdpMid = value;
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdpMid {
  resultIceUpdate.hasSdpMid = NO;
  resultIceUpdate.sdpMid = @"";
  return self;
}
- (BOOL) hasSdpMlineIndex {
  return resultIceUpdate.hasSdpMlineIndex;
}
- (UInt32) sdpMlineIndex {
  return resultIceUpdate.sdpMlineIndex;
}
- (SSKProtoCallMessageIceUpdateBuilder*) setSdpMlineIndex:(UInt32) value {
  resultIceUpdate.hasSdpMlineIndex = YES;
  resultIceUpdate.sdpMlineIndex = value;
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdpMlineIndex {
  resultIceUpdate.hasSdpMlineIndex = NO;
  resultIceUpdate.sdpMlineIndex = 0;
  return self;
}
- (BOOL) hasSdp {
  return resultIceUpdate.hasSdp;
}
- (NSString*) sdp {
  return resultIceUpdate.sdp;
}
- (SSKProtoCallMessageIceUpdateBuilder*) setSdp:(NSString*) value {
  resultIceUpdate.hasSdp = YES;
  resultIceUpdate.sdp = value;
  return self;
}
- (SSKProtoCallMessageIceUpdateBuilder*) clearSdp {
  resultIceUpdate.hasSdp = NO;
  resultIceUpdate.sdp = @"";
  return self;
}
@end

@interface SSKProtoCallMessageBusy ()
@property UInt64 id;
@end

@implementation SSKProtoCallMessageBusy

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
  }
  return self;
}
static SSKProtoCallMessageBusy* defaultSSKProtoCallMessageBusyInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessageBusy class]) {
    defaultSSKProtoCallMessageBusyInstance = [[SSKProtoCallMessageBusy alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageBusyInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageBusyInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessageBusy*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessageBusy*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageBusy*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessageBusy*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageBusy*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessageBusy*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageBusy*)[[[SSKProtoCallMessageBusy builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageBusyBuilder*) builder {
  return [[SSKProtoCallMessageBusyBuilder alloc] init];
}
+ (SSKProtoCallMessageBusyBuilder*) builderWithPrototype:(SSKProtoCallMessageBusy*) prototype {
  return [[SSKProtoCallMessageBusy builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageBusyBuilder*) builder {
  return [SSKProtoCallMessageBusy builder];
}
- (SSKProtoCallMessageBusyBuilder*) toBuilder {
  return [SSKProtoCallMessageBusy builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessageBusy class]]) {
    return NO;
  }
  SSKProtoCallMessageBusy *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageBusyBuilder()
@property (strong) SSKProtoCallMessageBusy* resultBusy;
@end

@implementation SSKProtoCallMessageBusyBuilder
@synthesize resultBusy;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultBusy = [[SSKProtoCallMessageBusy alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultBusy;
}
- (SSKProtoCallMessageBusyBuilder*) clear {
  self.resultBusy = [[SSKProtoCallMessageBusy alloc] init];
  return self;
}
- (SSKProtoCallMessageBusyBuilder*) clone {
  return [SSKProtoCallMessageBusy builderWithPrototype:resultBusy];
}
- (SSKProtoCallMessageBusy*) defaultInstance {
  return [SSKProtoCallMessageBusy defaultInstance];
}
- (SSKProtoCallMessageBusy*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessageBusy*) buildPartial {
  SSKProtoCallMessageBusy* returnMe = resultBusy;
  self.resultBusy = nil;
  return returnMe;
}
- (SSKProtoCallMessageBusyBuilder*) mergeFrom:(SSKProtoCallMessageBusy*) other {
  if (other == [SSKProtoCallMessageBusy defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageBusyBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageBusyBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultBusy.hasId;
}
- (UInt64) id {
  return resultBusy.id;
}
- (SSKProtoCallMessageBusyBuilder*) setId:(UInt64) value {
  resultBusy.hasId = YES;
  resultBusy.id = value;
  return self;
}
- (SSKProtoCallMessageBusyBuilder*) clearId {
  resultBusy.hasId = NO;
  resultBusy.id = 0L;
  return self;
}
@end

@interface SSKProtoCallMessageHangup ()
@property UInt64 id;
@end

@implementation SSKProtoCallMessageHangup

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
  }
  return self;
}
static SSKProtoCallMessageHangup* defaultSSKProtoCallMessageHangupInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoCallMessageHangup class]) {
    defaultSSKProtoCallMessageHangupInstance = [[SSKProtoCallMessageHangup alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageHangupInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoCallMessageHangupInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoCallMessageHangup*) parseFromData:(NSData*) data {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromData:data] build];
}
+ (SSKProtoCallMessageHangup*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageHangup*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromInputStream:input] build];
}
+ (SSKProtoCallMessageHangup*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageHangup*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoCallMessageHangup*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoCallMessageHangup*)[[[SSKProtoCallMessageHangup builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoCallMessageHangupBuilder*) builder {
  return [[SSKProtoCallMessageHangupBuilder alloc] init];
}
+ (SSKProtoCallMessageHangupBuilder*) builderWithPrototype:(SSKProtoCallMessageHangup*) prototype {
  return [[SSKProtoCallMessageHangup builder] mergeFrom:prototype];
}
- (SSKProtoCallMessageHangupBuilder*) builder {
  return [SSKProtoCallMessageHangup builder];
}
- (SSKProtoCallMessageHangupBuilder*) toBuilder {
  return [SSKProtoCallMessageHangup builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoCallMessageHangup class]]) {
    return NO;
  }
  SSKProtoCallMessageHangup *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoCallMessageHangupBuilder()
@property (strong) SSKProtoCallMessageHangup* resultHangup;
@end

@implementation SSKProtoCallMessageHangupBuilder
@synthesize resultHangup;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultHangup = [[SSKProtoCallMessageHangup alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultHangup;
}
- (SSKProtoCallMessageHangupBuilder*) clear {
  self.resultHangup = [[SSKProtoCallMessageHangup alloc] init];
  return self;
}
- (SSKProtoCallMessageHangupBuilder*) clone {
  return [SSKProtoCallMessageHangup builderWithPrototype:resultHangup];
}
- (SSKProtoCallMessageHangup*) defaultInstance {
  return [SSKProtoCallMessageHangup defaultInstance];
}
- (SSKProtoCallMessageHangup*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessageHangup*) buildPartial {
  SSKProtoCallMessageHangup* returnMe = resultHangup;
  self.resultHangup = nil;
  return returnMe;
}
- (SSKProtoCallMessageHangupBuilder*) mergeFrom:(SSKProtoCallMessageHangup*) other {
  if (other == [SSKProtoCallMessageHangup defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageHangupBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageHangupBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultHangup.hasId;
}
- (UInt64) id {
  return resultHangup.id;
}
- (SSKProtoCallMessageHangupBuilder*) setId:(UInt64) value {
  resultHangup.hasId = YES;
  resultHangup.id = value;
  return self;
}
- (SSKProtoCallMessageHangupBuilder*) clearId {
  resultHangup.hasId = NO;
  resultHangup.id = 0L;
  return self;
}
@end

@interface SSKProtoCallMessageBuilder()
@property (strong) SSKProtoCallMessage* resultCallMessage;
@end

@implementation SSKProtoCallMessageBuilder
@synthesize resultCallMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultCallMessage = [[SSKProtoCallMessage alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultCallMessage;
}
- (SSKProtoCallMessageBuilder*) clear {
  self.resultCallMessage = [[SSKProtoCallMessage alloc] init];
  return self;
}
- (SSKProtoCallMessageBuilder*) clone {
  return [SSKProtoCallMessage builderWithPrototype:resultCallMessage];
}
- (SSKProtoCallMessage*) defaultInstance {
  return [SSKProtoCallMessage defaultInstance];
}
- (SSKProtoCallMessage*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoCallMessage*) buildPartial {
  SSKProtoCallMessage* returnMe = resultCallMessage;
  self.resultCallMessage = nil;
  return returnMe;
}
- (SSKProtoCallMessageBuilder*) mergeFrom:(SSKProtoCallMessage*) other {
  if (other == [SSKProtoCallMessage defaultInstance]) {
    return self;
  }
  if (other.hasOffer) {
    [self mergeOffer:other.offer];
  }
  if (other.hasAnswer) {
    [self mergeAnswer:other.answer];
  }
  if (other.iceUpdateArray.count > 0) {
    if (resultCallMessage.iceUpdateArray == nil) {
      resultCallMessage.iceUpdateArray = [[NSMutableArray alloc] initWithArray:other.iceUpdateArray];
    } else {
      [resultCallMessage.iceUpdateArray addObjectsFromArray:other.iceUpdateArray];
    }
  }
  if (other.hasHangup) {
    [self mergeHangup:other.hangup];
  }
  if (other.hasBusy) {
    [self mergeBusy:other.busy];
  }
  if (other.hasProfileKey) {
    [self setProfileKey:other.profileKey];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoCallMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoCallMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoCallMessageOfferBuilder* subBuilder = [SSKProtoCallMessageOffer builder];
        if (self.hasOffer) {
          [subBuilder mergeFrom:self.offer];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setOffer:[subBuilder buildPartial]];
        break;
      }
      case 18: {
        SSKProtoCallMessageAnswerBuilder* subBuilder = [SSKProtoCallMessageAnswer builder];
        if (self.hasAnswer) {
          [subBuilder mergeFrom:self.answer];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAnswer:[subBuilder buildPartial]];
        break;
      }
      case 26: {
        SSKProtoCallMessageIceUpdateBuilder* subBuilder = [SSKProtoCallMessageIceUpdate builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addIceUpdate:[subBuilder buildPartial]];
        break;
      }
      case 34: {
        SSKProtoCallMessageHangupBuilder* subBuilder = [SSKProtoCallMessageHangup builder];
        if (self.hasHangup) {
          [subBuilder mergeFrom:self.hangup];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setHangup:[subBuilder buildPartial]];
        break;
      }
      case 42: {
        SSKProtoCallMessageBusyBuilder* subBuilder = [SSKProtoCallMessageBusy builder];
        if (self.hasBusy) {
          [subBuilder mergeFrom:self.busy];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setBusy:[subBuilder buildPartial]];
        break;
      }
      case 50: {
        [self setProfileKey:[input readData]];
        break;
      }
    }
  }
}
- (BOOL) hasOffer {
  return resultCallMessage.hasOffer;
}
- (SSKProtoCallMessageOffer*) offer {
  return resultCallMessage.offer;
}
- (SSKProtoCallMessageBuilder*) setOffer:(SSKProtoCallMessageOffer*) value {
  resultCallMessage.hasOffer = YES;
  resultCallMessage.offer = value;
  return self;
}
- (SSKProtoCallMessageBuilder*) setOfferBuilder:(SSKProtoCallMessageOfferBuilder*) builderForValue {
  return [self setOffer:[builderForValue build]];
}
- (SSKProtoCallMessageBuilder*) mergeOffer:(SSKProtoCallMessageOffer*) value {
  if (resultCallMessage.hasOffer &&
      resultCallMessage.offer != [SSKProtoCallMessageOffer defaultInstance]) {
    resultCallMessage.offer =
      [[[SSKProtoCallMessageOffer builderWithPrototype:resultCallMessage.offer] mergeFrom:value] buildPartial];
  } else {
    resultCallMessage.offer = value;
  }
  resultCallMessage.hasOffer = YES;
  return self;
}
- (SSKProtoCallMessageBuilder*) clearOffer {
  resultCallMessage.hasOffer = NO;
  resultCallMessage.offer = [SSKProtoCallMessageOffer defaultInstance];
  return self;
}
- (BOOL) hasAnswer {
  return resultCallMessage.hasAnswer;
}
- (SSKProtoCallMessageAnswer*) answer {
  return resultCallMessage.answer;
}
- (SSKProtoCallMessageBuilder*) setAnswer:(SSKProtoCallMessageAnswer*) value {
  resultCallMessage.hasAnswer = YES;
  resultCallMessage.answer = value;
  return self;
}
- (SSKProtoCallMessageBuilder*) setAnswerBuilder:(SSKProtoCallMessageAnswerBuilder*) builderForValue {
  return [self setAnswer:[builderForValue build]];
}
- (SSKProtoCallMessageBuilder*) mergeAnswer:(SSKProtoCallMessageAnswer*) value {
  if (resultCallMessage.hasAnswer &&
      resultCallMessage.answer != [SSKProtoCallMessageAnswer defaultInstance]) {
    resultCallMessage.answer =
      [[[SSKProtoCallMessageAnswer builderWithPrototype:resultCallMessage.answer] mergeFrom:value] buildPartial];
  } else {
    resultCallMessage.answer = value;
  }
  resultCallMessage.hasAnswer = YES;
  return self;
}
- (SSKProtoCallMessageBuilder*) clearAnswer {
  resultCallMessage.hasAnswer = NO;
  resultCallMessage.answer = [SSKProtoCallMessageAnswer defaultInstance];
  return self;
}
- (NSMutableArray<SSKProtoCallMessageIceUpdate*> *)iceUpdate {
  return resultCallMessage.iceUpdateArray;
}
- (SSKProtoCallMessageIceUpdate*)iceUpdateAtIndex:(NSUInteger)index {
  return [resultCallMessage iceUpdateAtIndex:index];
}
- (SSKProtoCallMessageBuilder *)addIceUpdate:(SSKProtoCallMessageIceUpdate*)value {
  if (resultCallMessage.iceUpdateArray == nil) {
    resultCallMessage.iceUpdateArray = [[NSMutableArray alloc]init];
  }
  [resultCallMessage.iceUpdateArray addObject:value];
  return self;
}
- (SSKProtoCallMessageBuilder *)setIceUpdateArray:(NSArray<SSKProtoCallMessageIceUpdate*> *)array {
  resultCallMessage.iceUpdateArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoCallMessageBuilder *)clearIceUpdate {
  resultCallMessage.iceUpdateArray = nil;
  return self;
}
- (BOOL) hasHangup {
  return resultCallMessage.hasHangup;
}
- (SSKProtoCallMessageHangup*) hangup {
  return resultCallMessage.hangup;
}
- (SSKProtoCallMessageBuilder*) setHangup:(SSKProtoCallMessageHangup*) value {
  resultCallMessage.hasHangup = YES;
  resultCallMessage.hangup = value;
  return self;
}
- (SSKProtoCallMessageBuilder*) setHangupBuilder:(SSKProtoCallMessageHangupBuilder*) builderForValue {
  return [self setHangup:[builderForValue build]];
}
- (SSKProtoCallMessageBuilder*) mergeHangup:(SSKProtoCallMessageHangup*) value {
  if (resultCallMessage.hasHangup &&
      resultCallMessage.hangup != [SSKProtoCallMessageHangup defaultInstance]) {
    resultCallMessage.hangup =
      [[[SSKProtoCallMessageHangup builderWithPrototype:resultCallMessage.hangup] mergeFrom:value] buildPartial];
  } else {
    resultCallMessage.hangup = value;
  }
  resultCallMessage.hasHangup = YES;
  return self;
}
- (SSKProtoCallMessageBuilder*) clearHangup {
  resultCallMessage.hasHangup = NO;
  resultCallMessage.hangup = [SSKProtoCallMessageHangup defaultInstance];
  return self;
}
- (BOOL) hasBusy {
  return resultCallMessage.hasBusy;
}
- (SSKProtoCallMessageBusy*) busy {
  return resultCallMessage.busy;
}
- (SSKProtoCallMessageBuilder*) setBusy:(SSKProtoCallMessageBusy*) value {
  resultCallMessage.hasBusy = YES;
  resultCallMessage.busy = value;
  return self;
}
- (SSKProtoCallMessageBuilder*) setBusyBuilder:(SSKProtoCallMessageBusyBuilder*) builderForValue {
  return [self setBusy:[builderForValue build]];
}
- (SSKProtoCallMessageBuilder*) mergeBusy:(SSKProtoCallMessageBusy*) value {
  if (resultCallMessage.hasBusy &&
      resultCallMessage.busy != [SSKProtoCallMessageBusy defaultInstance]) {
    resultCallMessage.busy =
      [[[SSKProtoCallMessageBusy builderWithPrototype:resultCallMessage.busy] mergeFrom:value] buildPartial];
  } else {
    resultCallMessage.busy = value;
  }
  resultCallMessage.hasBusy = YES;
  return self;
}
- (SSKProtoCallMessageBuilder*) clearBusy {
  resultCallMessage.hasBusy = NO;
  resultCallMessage.busy = [SSKProtoCallMessageBusy defaultInstance];
  return self;
}
- (BOOL) hasProfileKey {
  return resultCallMessage.hasProfileKey;
}
- (NSData*) profileKey {
  return resultCallMessage.profileKey;
}
- (SSKProtoCallMessageBuilder*) setProfileKey:(NSData*) value {
  resultCallMessage.hasProfileKey = YES;
  resultCallMessage.profileKey = value;
  return self;
}
- (SSKProtoCallMessageBuilder*) clearProfileKey {
  resultCallMessage.hasProfileKey = NO;
  resultCallMessage.profileKey = [NSData data];
  return self;
}
@end

@interface SSKProtoDataMessage ()
@property (strong) NSString* body;
@property (strong) NSMutableArray<SSKProtoAttachmentPointer*> * attachmentsArray;
@property (strong) SSKProtoGroupContext* group;
@property UInt32 flags;
@property UInt32 expireTimer;
@property (strong) NSData* profileKey;
@property UInt64 timestamp;
@property (strong) SSKProtoDataMessageQuote* quote;
@property (strong) NSMutableArray<SSKProtoDataMessageContact*> * contactArray;
@end

@implementation SSKProtoDataMessage

- (BOOL) hasBody {
  return !!hasBody_;
}
- (void) setHasBody:(BOOL) _value_ {
  hasBody_ = !!_value_;
}
@synthesize body;
@synthesize attachmentsArray;
@dynamic attachments;
- (BOOL) hasGroup {
  return !!hasGroup_;
}
- (void) setHasGroup:(BOOL) _value_ {
  hasGroup_ = !!_value_;
}
@synthesize group;
- (BOOL) hasFlags {
  return !!hasFlags_;
}
- (void) setHasFlags:(BOOL) _value_ {
  hasFlags_ = !!_value_;
}
@synthesize flags;
- (BOOL) hasExpireTimer {
  return !!hasExpireTimer_;
}
- (void) setHasExpireTimer:(BOOL) _value_ {
  hasExpireTimer_ = !!_value_;
}
@synthesize expireTimer;
- (BOOL) hasProfileKey {
  return !!hasProfileKey_;
}
- (void) setHasProfileKey:(BOOL) _value_ {
  hasProfileKey_ = !!_value_;
}
@synthesize profileKey;
- (BOOL) hasTimestamp {
  return !!hasTimestamp_;
}
- (void) setHasTimestamp:(BOOL) _value_ {
  hasTimestamp_ = !!_value_;
}
@synthesize timestamp;
- (BOOL) hasQuote {
  return !!hasQuote_;
}
- (void) setHasQuote:(BOOL) _value_ {
  hasQuote_ = !!_value_;
}
@synthesize quote;
@synthesize contactArray;
@dynamic contact;
- (instancetype) init {
  if ((self = [super init])) {
    self.body = @"";
    self.group = [SSKProtoGroupContext defaultInstance];
    self.flags = 0;
    self.expireTimer = 0;
    self.profileKey = [NSData data];
    self.timestamp = 0L;
    self.quote = [SSKProtoDataMessageQuote defaultInstance];
  }
  return self;
}
static SSKProtoDataMessage* defaultSSKProtoDataMessageInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessage class]) {
    defaultSSKProtoDataMessageInstance = [[SSKProtoDataMessage alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageInstance;
}
- (NSArray<SSKProtoAttachmentPointer*> *)attachments {
  return attachmentsArray;
}
- (SSKProtoAttachmentPointer*)attachmentsAtIndex:(NSUInteger)index {
  return [attachmentsArray objectAtIndex:index];
}
- (NSArray<SSKProtoDataMessageContact*> *)contact {
  return contactArray;
}
- (SSKProtoDataMessageContact*)contactAtIndex:(NSUInteger)index {
  return [contactArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasBody) {
    [output writeString:1 value:self.body];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoAttachmentPointer *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:2 value:element];
  }];
  if (self.hasGroup) {
    [output writeMessage:3 value:self.group];
  }
  if (self.hasFlags) {
    [output writeUInt32:4 value:self.flags];
  }
  if (self.hasExpireTimer) {
    [output writeUInt32:5 value:self.expireTimer];
  }
  if (self.hasProfileKey) {
    [output writeData:6 value:self.profileKey];
  }
  if (self.hasTimestamp) {
    [output writeUInt64:7 value:self.timestamp];
  }
  if (self.hasQuote) {
    [output writeMessage:8 value:self.quote];
  }
  [self.contactArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContact *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:9 value:element];
  }];
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasBody) {
    size_ += computeStringSize(1, self.body);
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoAttachmentPointer *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(2, element);
  }];
  if (self.hasGroup) {
    size_ += computeMessageSize(3, self.group);
  }
  if (self.hasFlags) {
    size_ += computeUInt32Size(4, self.flags);
  }
  if (self.hasExpireTimer) {
    size_ += computeUInt32Size(5, self.expireTimer);
  }
  if (self.hasProfileKey) {
    size_ += computeDataSize(6, self.profileKey);
  }
  if (self.hasTimestamp) {
    size_ += computeUInt64Size(7, self.timestamp);
  }
  if (self.hasQuote) {
    size_ += computeMessageSize(8, self.quote);
  }
  [self.contactArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContact *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(9, element);
  }];
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessage*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessage*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessage*)[[[SSKProtoDataMessage builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageBuilder*) builder {
  return [[SSKProtoDataMessageBuilder alloc] init];
}
+ (SSKProtoDataMessageBuilder*) builderWithPrototype:(SSKProtoDataMessage*) prototype {
  return [[SSKProtoDataMessage builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageBuilder*) builder {
  return [SSKProtoDataMessage builder];
}
- (SSKProtoDataMessageBuilder*) toBuilder {
  return [SSKProtoDataMessage builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasBody) {
    [output appendFormat:@"%@%@: %@\n", indent, @"body", self.body];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoAttachmentPointer *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"attachments"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  if (self.hasGroup) {
    [output appendFormat:@"%@%@ {\n", indent, @"group"];
    [self.group writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasFlags) {
    [output appendFormat:@"%@%@: %@\n", indent, @"flags", [NSNumber numberWithInteger:self.flags]];
  }
  if (self.hasExpireTimer) {
    [output appendFormat:@"%@%@: %@\n", indent, @"expireTimer", [NSNumber numberWithInteger:self.expireTimer]];
  }
  if (self.hasProfileKey) {
    [output appendFormat:@"%@%@: %@\n", indent, @"profileKey", self.profileKey];
  }
  if (self.hasTimestamp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"timestamp", [NSNumber numberWithLongLong:self.timestamp]];
  }
  if (self.hasQuote) {
    [output appendFormat:@"%@%@ {\n", indent, @"quote"];
    [self.quote writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.contactArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContact *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"contact"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasBody) {
    [dictionary setObject: self.body forKey: @"body"];
  }
  for (SSKProtoAttachmentPointer* element in self.attachmentsArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"attachments"];
  }
  if (self.hasGroup) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.group storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"group"];
  }
  if (self.hasFlags) {
    [dictionary setObject: [NSNumber numberWithInteger:self.flags] forKey: @"flags"];
  }
  if (self.hasExpireTimer) {
    [dictionary setObject: [NSNumber numberWithInteger:self.expireTimer] forKey: @"expireTimer"];
  }
  if (self.hasProfileKey) {
    [dictionary setObject: self.profileKey forKey: @"profileKey"];
  }
  if (self.hasTimestamp) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.timestamp] forKey: @"timestamp"];
  }
  if (self.hasQuote) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.quote storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"quote"];
  }
  for (SSKProtoDataMessageContact* element in self.contactArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"contact"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessage class]]) {
    return NO;
  }
  SSKProtoDataMessage *otherMessage = other;
  return
      self.hasBody == otherMessage.hasBody &&
      (!self.hasBody || [self.body isEqual:otherMessage.body]) &&
      [self.attachmentsArray isEqualToArray:otherMessage.attachmentsArray] &&
      self.hasGroup == otherMessage.hasGroup &&
      (!self.hasGroup || [self.group isEqual:otherMessage.group]) &&
      self.hasFlags == otherMessage.hasFlags &&
      (!self.hasFlags || self.flags == otherMessage.flags) &&
      self.hasExpireTimer == otherMessage.hasExpireTimer &&
      (!self.hasExpireTimer || self.expireTimer == otherMessage.expireTimer) &&
      self.hasProfileKey == otherMessage.hasProfileKey &&
      (!self.hasProfileKey || [self.profileKey isEqual:otherMessage.profileKey]) &&
      self.hasTimestamp == otherMessage.hasTimestamp &&
      (!self.hasTimestamp || self.timestamp == otherMessage.timestamp) &&
      self.hasQuote == otherMessage.hasQuote &&
      (!self.hasQuote || [self.quote isEqual:otherMessage.quote]) &&
      [self.contactArray isEqualToArray:otherMessage.contactArray] &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasBody) {
    hashCode = hashCode * 31 + [self.body hash];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoAttachmentPointer *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasGroup) {
    hashCode = hashCode * 31 + [self.group hash];
  }
  if (self.hasFlags) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.flags] hash];
  }
  if (self.hasExpireTimer) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.expireTimer] hash];
  }
  if (self.hasProfileKey) {
    hashCode = hashCode * 31 + [self.profileKey hash];
  }
  if (self.hasTimestamp) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.timestamp] hash];
  }
  if (self.hasQuote) {
    hashCode = hashCode * 31 + [self.quote hash];
  }
  [self.contactArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContact *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoDataMessageFlagsIsValidValue(SSKProtoDataMessageFlags value) {
  switch (value) {
    case SSKProtoDataMessageFlagsEndSession:
    case SSKProtoDataMessageFlagsExpirationTimerUpdate:
    case SSKProtoDataMessageFlagsProfileKeyUpdate:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoDataMessageFlags(SSKProtoDataMessageFlags value) {
  switch (value) {
    case SSKProtoDataMessageFlagsEndSession:
      return @"SSKProtoDataMessageFlagsEndSession";
    case SSKProtoDataMessageFlagsExpirationTimerUpdate:
      return @"SSKProtoDataMessageFlagsExpirationTimerUpdate";
    case SSKProtoDataMessageFlagsProfileKeyUpdate:
      return @"SSKProtoDataMessageFlagsProfileKeyUpdate";
    default:
      return nil;
  }
}

@interface SSKProtoDataMessageQuote ()
@property UInt64 id;
@property (strong) NSString* author;
@property (strong) NSString* text;
@property (strong) NSMutableArray<SSKProtoDataMessageQuoteQuotedAttachment*> * attachmentsArray;
@end

@implementation SSKProtoDataMessageQuote

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasAuthor {
  return !!hasAuthor_;
}
- (void) setHasAuthor:(BOOL) _value_ {
  hasAuthor_ = !!_value_;
}
@synthesize author;
- (BOOL) hasText {
  return !!hasText_;
}
- (void) setHasText:(BOOL) _value_ {
  hasText_ = !!_value_;
}
@synthesize text;
@synthesize attachmentsArray;
@dynamic attachments;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
    self.author = @"";
    self.text = @"";
  }
  return self;
}
static SSKProtoDataMessageQuote* defaultSSKProtoDataMessageQuoteInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageQuote class]) {
    defaultSSKProtoDataMessageQuoteInstance = [[SSKProtoDataMessageQuote alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageQuoteInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageQuoteInstance;
}
- (NSArray<SSKProtoDataMessageQuoteQuotedAttachment*> *)attachments {
  return attachmentsArray;
}
- (SSKProtoDataMessageQuoteQuotedAttachment*)attachmentsAtIndex:(NSUInteger)index {
  return [attachmentsArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeUInt64:1 value:self.id];
  }
  if (self.hasAuthor) {
    [output writeString:2 value:self.author];
  }
  if (self.hasText) {
    [output writeString:3 value:self.text];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageQuoteQuotedAttachment *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:4 value:element];
  }];
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeUInt64Size(1, self.id);
  }
  if (self.hasAuthor) {
    size_ += computeStringSize(2, self.author);
  }
  if (self.hasText) {
    size_ += computeStringSize(3, self.text);
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageQuoteQuotedAttachment *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(4, element);
  }];
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageQuote*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageQuote*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuote*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageQuote*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuote*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageQuote*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuote*)[[[SSKProtoDataMessageQuote builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuoteBuilder*) builder {
  return [[SSKProtoDataMessageQuoteBuilder alloc] init];
}
+ (SSKProtoDataMessageQuoteBuilder*) builderWithPrototype:(SSKProtoDataMessageQuote*) prototype {
  return [[SSKProtoDataMessageQuote builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageQuoteBuilder*) builder {
  return [SSKProtoDataMessageQuote builder];
}
- (SSKProtoDataMessageQuoteBuilder*) toBuilder {
  return [SSKProtoDataMessageQuote builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  if (self.hasAuthor) {
    [output appendFormat:@"%@%@: %@\n", indent, @"author", self.author];
  }
  if (self.hasText) {
    [output appendFormat:@"%@%@: %@\n", indent, @"text", self.text];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageQuoteQuotedAttachment *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"attachments"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  if (self.hasAuthor) {
    [dictionary setObject: self.author forKey: @"author"];
  }
  if (self.hasText) {
    [dictionary setObject: self.text forKey: @"text"];
  }
  for (SSKProtoDataMessageQuoteQuotedAttachment* element in self.attachmentsArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"attachments"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageQuote class]]) {
    return NO;
  }
  SSKProtoDataMessageQuote *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      self.hasAuthor == otherMessage.hasAuthor &&
      (!self.hasAuthor || [self.author isEqual:otherMessage.author]) &&
      self.hasText == otherMessage.hasText &&
      (!self.hasText || [self.text isEqual:otherMessage.text]) &&
      [self.attachmentsArray isEqualToArray:otherMessage.attachmentsArray] &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  if (self.hasAuthor) {
    hashCode = hashCode * 31 + [self.author hash];
  }
  if (self.hasText) {
    hashCode = hashCode * 31 + [self.text hash];
  }
  [self.attachmentsArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageQuoteQuotedAttachment *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoDataMessageQuoteQuotedAttachment ()
@property (strong) NSString* contentType;
@property (strong) NSString* fileName;
@property (strong) SSKProtoAttachmentPointer* thumbnail;
@property UInt32 flags;
@end

@implementation SSKProtoDataMessageQuoteQuotedAttachment

- (BOOL) hasContentType {
  return !!hasContentType_;
}
- (void) setHasContentType:(BOOL) _value_ {
  hasContentType_ = !!_value_;
}
@synthesize contentType;
- (BOOL) hasFileName {
  return !!hasFileName_;
}
- (void) setHasFileName:(BOOL) _value_ {
  hasFileName_ = !!_value_;
}
@synthesize fileName;
- (BOOL) hasThumbnail {
  return !!hasThumbnail_;
}
- (void) setHasThumbnail:(BOOL) _value_ {
  hasThumbnail_ = !!_value_;
}
@synthesize thumbnail;
- (BOOL) hasFlags {
  return !!hasFlags_;
}
- (void) setHasFlags:(BOOL) _value_ {
  hasFlags_ = !!_value_;
}
@synthesize flags;
- (instancetype) init {
  if ((self = [super init])) {
    self.contentType = @"";
    self.fileName = @"";
    self.thumbnail = [SSKProtoAttachmentPointer defaultInstance];
    self.flags = 0;
  }
  return self;
}
static SSKProtoDataMessageQuoteQuotedAttachment* defaultSSKProtoDataMessageQuoteQuotedAttachmentInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageQuoteQuotedAttachment class]) {
    defaultSSKProtoDataMessageQuoteQuotedAttachmentInstance = [[SSKProtoDataMessageQuoteQuotedAttachment alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageQuoteQuotedAttachmentInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageQuoteQuotedAttachmentInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasContentType) {
    [output writeString:1 value:self.contentType];
  }
  if (self.hasFileName) {
    [output writeString:2 value:self.fileName];
  }
  if (self.hasThumbnail) {
    [output writeMessage:3 value:self.thumbnail];
  }
  if (self.hasFlags) {
    [output writeUInt32:4 value:self.flags];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasContentType) {
    size_ += computeStringSize(1, self.contentType);
  }
  if (self.hasFileName) {
    size_ += computeStringSize(2, self.fileName);
  }
  if (self.hasThumbnail) {
    size_ += computeMessageSize(3, self.thumbnail);
  }
  if (self.hasFlags) {
    size_ += computeUInt32Size(4, self.flags);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachment*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageQuoteQuotedAttachment*)[[[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builder {
  return [[SSKProtoDataMessageQuoteQuotedAttachmentBuilder alloc] init];
}
+ (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builderWithPrototype:(SSKProtoDataMessageQuoteQuotedAttachment*) prototype {
  return [[SSKProtoDataMessageQuoteQuotedAttachment builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) builder {
  return [SSKProtoDataMessageQuoteQuotedAttachment builder];
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) toBuilder {
  return [SSKProtoDataMessageQuoteQuotedAttachment builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasContentType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"contentType", self.contentType];
  }
  if (self.hasFileName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"fileName", self.fileName];
  }
  if (self.hasThumbnail) {
    [output appendFormat:@"%@%@ {\n", indent, @"thumbnail"];
    [self.thumbnail writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasFlags) {
    [output appendFormat:@"%@%@: %@\n", indent, @"flags", [NSNumber numberWithInteger:self.flags]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasContentType) {
    [dictionary setObject: self.contentType forKey: @"contentType"];
  }
  if (self.hasFileName) {
    [dictionary setObject: self.fileName forKey: @"fileName"];
  }
  if (self.hasThumbnail) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.thumbnail storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"thumbnail"];
  }
  if (self.hasFlags) {
    [dictionary setObject: [NSNumber numberWithInteger:self.flags] forKey: @"flags"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageQuoteQuotedAttachment class]]) {
    return NO;
  }
  SSKProtoDataMessageQuoteQuotedAttachment *otherMessage = other;
  return
      self.hasContentType == otherMessage.hasContentType &&
      (!self.hasContentType || [self.contentType isEqual:otherMessage.contentType]) &&
      self.hasFileName == otherMessage.hasFileName &&
      (!self.hasFileName || [self.fileName isEqual:otherMessage.fileName]) &&
      self.hasThumbnail == otherMessage.hasThumbnail &&
      (!self.hasThumbnail || [self.thumbnail isEqual:otherMessage.thumbnail]) &&
      self.hasFlags == otherMessage.hasFlags &&
      (!self.hasFlags || self.flags == otherMessage.flags) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasContentType) {
    hashCode = hashCode * 31 + [self.contentType hash];
  }
  if (self.hasFileName) {
    hashCode = hashCode * 31 + [self.fileName hash];
  }
  if (self.hasThumbnail) {
    hashCode = hashCode * 31 + [self.thumbnail hash];
  }
  if (self.hasFlags) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.flags] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoDataMessageQuoteQuotedAttachmentFlagsIsValidValue(SSKProtoDataMessageQuoteQuotedAttachmentFlags value) {
  switch (value) {
    case SSKProtoDataMessageQuoteQuotedAttachmentFlagsVoiceMessage:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoDataMessageQuoteQuotedAttachmentFlags(SSKProtoDataMessageQuoteQuotedAttachmentFlags value) {
  switch (value) {
    case SSKProtoDataMessageQuoteQuotedAttachmentFlagsVoiceMessage:
      return @"SSKProtoDataMessageQuoteQuotedAttachmentFlagsVoiceMessage";
    default:
      return nil;
  }
}

@interface SSKProtoDataMessageQuoteQuotedAttachmentBuilder()
@property (strong) SSKProtoDataMessageQuoteQuotedAttachment* resultQuotedAttachment;
@end

@implementation SSKProtoDataMessageQuoteQuotedAttachmentBuilder
@synthesize resultQuotedAttachment;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultQuotedAttachment = [[SSKProtoDataMessageQuoteQuotedAttachment alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultQuotedAttachment;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clear {
  self.resultQuotedAttachment = [[SSKProtoDataMessageQuoteQuotedAttachment alloc] init];
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clone {
  return [SSKProtoDataMessageQuoteQuotedAttachment builderWithPrototype:resultQuotedAttachment];
}
- (SSKProtoDataMessageQuoteQuotedAttachment*) defaultInstance {
  return [SSKProtoDataMessageQuoteQuotedAttachment defaultInstance];
}
- (SSKProtoDataMessageQuoteQuotedAttachment*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageQuoteQuotedAttachment*) buildPartial {
  SSKProtoDataMessageQuoteQuotedAttachment* returnMe = resultQuotedAttachment;
  self.resultQuotedAttachment = nil;
  return returnMe;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFrom:(SSKProtoDataMessageQuoteQuotedAttachment*) other {
  if (other == [SSKProtoDataMessageQuoteQuotedAttachment defaultInstance]) {
    return self;
  }
  if (other.hasContentType) {
    [self setContentType:other.contentType];
  }
  if (other.hasFileName) {
    [self setFileName:other.fileName];
  }
  if (other.hasThumbnail) {
    [self mergeThumbnail:other.thumbnail];
  }
  if (other.hasFlags) {
    [self setFlags:other.flags];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setContentType:[input readString]];
        break;
      }
      case 18: {
        [self setFileName:[input readString]];
        break;
      }
      case 26: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        if (self.hasThumbnail) {
          [subBuilder mergeFrom:self.thumbnail];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setThumbnail:[subBuilder buildPartial]];
        break;
      }
      case 32: {
        [self setFlags:[input readUInt32]];
        break;
      }
    }
  }
}
- (BOOL) hasContentType {
  return resultQuotedAttachment.hasContentType;
}
- (NSString*) contentType {
  return resultQuotedAttachment.contentType;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setContentType:(NSString*) value {
  resultQuotedAttachment.hasContentType = YES;
  resultQuotedAttachment.contentType = value;
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearContentType {
  resultQuotedAttachment.hasContentType = NO;
  resultQuotedAttachment.contentType = @"";
  return self;
}
- (BOOL) hasFileName {
  return resultQuotedAttachment.hasFileName;
}
- (NSString*) fileName {
  return resultQuotedAttachment.fileName;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setFileName:(NSString*) value {
  resultQuotedAttachment.hasFileName = YES;
  resultQuotedAttachment.fileName = value;
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearFileName {
  resultQuotedAttachment.hasFileName = NO;
  resultQuotedAttachment.fileName = @"";
  return self;
}
- (BOOL) hasThumbnail {
  return resultQuotedAttachment.hasThumbnail;
}
- (SSKProtoAttachmentPointer*) thumbnail {
  return resultQuotedAttachment.thumbnail;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setThumbnail:(SSKProtoAttachmentPointer*) value {
  resultQuotedAttachment.hasThumbnail = YES;
  resultQuotedAttachment.thumbnail = value;
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setThumbnailBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue {
  return [self setThumbnail:[builderForValue build]];
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) mergeThumbnail:(SSKProtoAttachmentPointer*) value {
  if (resultQuotedAttachment.hasThumbnail &&
      resultQuotedAttachment.thumbnail != [SSKProtoAttachmentPointer defaultInstance]) {
    resultQuotedAttachment.thumbnail =
      [[[SSKProtoAttachmentPointer builderWithPrototype:resultQuotedAttachment.thumbnail] mergeFrom:value] buildPartial];
  } else {
    resultQuotedAttachment.thumbnail = value;
  }
  resultQuotedAttachment.hasThumbnail = YES;
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearThumbnail {
  resultQuotedAttachment.hasThumbnail = NO;
  resultQuotedAttachment.thumbnail = [SSKProtoAttachmentPointer defaultInstance];
  return self;
}
- (BOOL) hasFlags {
  return resultQuotedAttachment.hasFlags;
}
- (UInt32) flags {
  return resultQuotedAttachment.flags;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) setFlags:(UInt32) value {
  resultQuotedAttachment.hasFlags = YES;
  resultQuotedAttachment.flags = value;
  return self;
}
- (SSKProtoDataMessageQuoteQuotedAttachmentBuilder*) clearFlags {
  resultQuotedAttachment.hasFlags = NO;
  resultQuotedAttachment.flags = 0;
  return self;
}
@end

@interface SSKProtoDataMessageQuoteBuilder()
@property (strong) SSKProtoDataMessageQuote* resultQuote;
@end

@implementation SSKProtoDataMessageQuoteBuilder
@synthesize resultQuote;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultQuote = [[SSKProtoDataMessageQuote alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultQuote;
}
- (SSKProtoDataMessageQuoteBuilder*) clear {
  self.resultQuote = [[SSKProtoDataMessageQuote alloc] init];
  return self;
}
- (SSKProtoDataMessageQuoteBuilder*) clone {
  return [SSKProtoDataMessageQuote builderWithPrototype:resultQuote];
}
- (SSKProtoDataMessageQuote*) defaultInstance {
  return [SSKProtoDataMessageQuote defaultInstance];
}
- (SSKProtoDataMessageQuote*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageQuote*) buildPartial {
  SSKProtoDataMessageQuote* returnMe = resultQuote;
  self.resultQuote = nil;
  return returnMe;
}
- (SSKProtoDataMessageQuoteBuilder*) mergeFrom:(SSKProtoDataMessageQuote*) other {
  if (other == [SSKProtoDataMessageQuote defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasAuthor) {
    [self setAuthor:other.author];
  }
  if (other.hasText) {
    [self setText:other.text];
  }
  if (other.attachmentsArray.count > 0) {
    if (resultQuote.attachmentsArray == nil) {
      resultQuote.attachmentsArray = [[NSMutableArray alloc] initWithArray:other.attachmentsArray];
    } else {
      [resultQuote.attachmentsArray addObjectsFromArray:other.attachmentsArray];
    }
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageQuoteBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageQuoteBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setId:[input readUInt64]];
        break;
      }
      case 18: {
        [self setAuthor:[input readString]];
        break;
      }
      case 26: {
        [self setText:[input readString]];
        break;
      }
      case 34: {
        SSKProtoDataMessageQuoteQuotedAttachmentBuilder* subBuilder = [SSKProtoDataMessageQuoteQuotedAttachment builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addAttachments:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultQuote.hasId;
}
- (UInt64) id {
  return resultQuote.id;
}
- (SSKProtoDataMessageQuoteBuilder*) setId:(UInt64) value {
  resultQuote.hasId = YES;
  resultQuote.id = value;
  return self;
}
- (SSKProtoDataMessageQuoteBuilder*) clearId {
  resultQuote.hasId = NO;
  resultQuote.id = 0L;
  return self;
}
- (BOOL) hasAuthor {
  return resultQuote.hasAuthor;
}
- (NSString*) author {
  return resultQuote.author;
}
- (SSKProtoDataMessageQuoteBuilder*) setAuthor:(NSString*) value {
  resultQuote.hasAuthor = YES;
  resultQuote.author = value;
  return self;
}
- (SSKProtoDataMessageQuoteBuilder*) clearAuthor {
  resultQuote.hasAuthor = NO;
  resultQuote.author = @"";
  return self;
}
- (BOOL) hasText {
  return resultQuote.hasText;
}
- (NSString*) text {
  return resultQuote.text;
}
- (SSKProtoDataMessageQuoteBuilder*) setText:(NSString*) value {
  resultQuote.hasText = YES;
  resultQuote.text = value;
  return self;
}
- (SSKProtoDataMessageQuoteBuilder*) clearText {
  resultQuote.hasText = NO;
  resultQuote.text = @"";
  return self;
}
- (NSMutableArray<SSKProtoDataMessageQuoteQuotedAttachment*> *)attachments {
  return resultQuote.attachmentsArray;
}
- (SSKProtoDataMessageQuoteQuotedAttachment*)attachmentsAtIndex:(NSUInteger)index {
  return [resultQuote attachmentsAtIndex:index];
}
- (SSKProtoDataMessageQuoteBuilder *)addAttachments:(SSKProtoDataMessageQuoteQuotedAttachment*)value {
  if (resultQuote.attachmentsArray == nil) {
    resultQuote.attachmentsArray = [[NSMutableArray alloc]init];
  }
  [resultQuote.attachmentsArray addObject:value];
  return self;
}
- (SSKProtoDataMessageQuoteBuilder *)setAttachmentsArray:(NSArray<SSKProtoDataMessageQuoteQuotedAttachment*> *)array {
  resultQuote.attachmentsArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageQuoteBuilder *)clearAttachments {
  resultQuote.attachmentsArray = nil;
  return self;
}
@end

@interface SSKProtoDataMessageContact ()
@property (strong) SSKProtoDataMessageContactName* name;
@property (strong) NSMutableArray<SSKProtoDataMessageContactPhone*> * numberArray;
@property (strong) NSMutableArray<SSKProtoDataMessageContactEmail*> * emailArray;
@property (strong) NSMutableArray<SSKProtoDataMessageContactPostalAddress*> * addressArray;
@property (strong) SSKProtoDataMessageContactAvatar* avatar;
@property (strong) NSString* organization;
@end

@implementation SSKProtoDataMessageContact

- (BOOL) hasName {
  return !!hasName_;
}
- (void) setHasName:(BOOL) _value_ {
  hasName_ = !!_value_;
}
@synthesize name;
@synthesize numberArray;
@dynamic number;
@synthesize emailArray;
@dynamic email;
@synthesize addressArray;
@dynamic address;
- (BOOL) hasAvatar {
  return !!hasAvatar_;
}
- (void) setHasAvatar:(BOOL) _value_ {
  hasAvatar_ = !!_value_;
}
@synthesize avatar;
- (BOOL) hasOrganization {
  return !!hasOrganization_;
}
- (void) setHasOrganization:(BOOL) _value_ {
  hasOrganization_ = !!_value_;
}
@synthesize organization;
- (instancetype) init {
  if ((self = [super init])) {
    self.name = [SSKProtoDataMessageContactName defaultInstance];
    self.avatar = [SSKProtoDataMessageContactAvatar defaultInstance];
    self.organization = @"";
  }
  return self;
}
static SSKProtoDataMessageContact* defaultSSKProtoDataMessageContactInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContact class]) {
    defaultSSKProtoDataMessageContactInstance = [[SSKProtoDataMessageContact alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactInstance;
}
- (NSArray<SSKProtoDataMessageContactPhone*> *)number {
  return numberArray;
}
- (SSKProtoDataMessageContactPhone*)numberAtIndex:(NSUInteger)index {
  return [numberArray objectAtIndex:index];
}
- (NSArray<SSKProtoDataMessageContactEmail*> *)email {
  return emailArray;
}
- (SSKProtoDataMessageContactEmail*)emailAtIndex:(NSUInteger)index {
  return [emailArray objectAtIndex:index];
}
- (NSArray<SSKProtoDataMessageContactPostalAddress*> *)address {
  return addressArray;
}
- (SSKProtoDataMessageContactPostalAddress*)addressAtIndex:(NSUInteger)index {
  return [addressArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasName) {
    [output writeMessage:1 value:self.name];
  }
  [self.numberArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPhone *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:3 value:element];
  }];
  [self.emailArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactEmail *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:4 value:element];
  }];
  [self.addressArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPostalAddress *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:5 value:element];
  }];
  if (self.hasAvatar) {
    [output writeMessage:6 value:self.avatar];
  }
  if (self.hasOrganization) {
    [output writeString:7 value:self.organization];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasName) {
    size_ += computeMessageSize(1, self.name);
  }
  [self.numberArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPhone *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(3, element);
  }];
  [self.emailArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactEmail *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(4, element);
  }];
  [self.addressArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPostalAddress *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(5, element);
  }];
  if (self.hasAvatar) {
    size_ += computeMessageSize(6, self.avatar);
  }
  if (self.hasOrganization) {
    size_ += computeStringSize(7, self.organization);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContact*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContact*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContact*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContact*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContact*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContact*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContact*)[[[SSKProtoDataMessageContact builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactBuilder*) builder {
  return [[SSKProtoDataMessageContactBuilder alloc] init];
}
+ (SSKProtoDataMessageContactBuilder*) builderWithPrototype:(SSKProtoDataMessageContact*) prototype {
  return [[SSKProtoDataMessageContact builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactBuilder*) builder {
  return [SSKProtoDataMessageContact builder];
}
- (SSKProtoDataMessageContactBuilder*) toBuilder {
  return [SSKProtoDataMessageContact builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasName) {
    [output appendFormat:@"%@%@ {\n", indent, @"name"];
    [self.name writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.numberArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPhone *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"number"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  [self.emailArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactEmail *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"email"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  [self.addressArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPostalAddress *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"address"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  if (self.hasAvatar) {
    [output appendFormat:@"%@%@ {\n", indent, @"avatar"];
    [self.avatar writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasOrganization) {
    [output appendFormat:@"%@%@: %@\n", indent, @"organization", self.organization];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasName) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.name storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"name"];
  }
  for (SSKProtoDataMessageContactPhone* element in self.numberArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"number"];
  }
  for (SSKProtoDataMessageContactEmail* element in self.emailArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"email"];
  }
  for (SSKProtoDataMessageContactPostalAddress* element in self.addressArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"address"];
  }
  if (self.hasAvatar) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.avatar storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"avatar"];
  }
  if (self.hasOrganization) {
    [dictionary setObject: self.organization forKey: @"organization"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContact class]]) {
    return NO;
  }
  SSKProtoDataMessageContact *otherMessage = other;
  return
      self.hasName == otherMessage.hasName &&
      (!self.hasName || [self.name isEqual:otherMessage.name]) &&
      [self.numberArray isEqualToArray:otherMessage.numberArray] &&
      [self.emailArray isEqualToArray:otherMessage.emailArray] &&
      [self.addressArray isEqualToArray:otherMessage.addressArray] &&
      self.hasAvatar == otherMessage.hasAvatar &&
      (!self.hasAvatar || [self.avatar isEqual:otherMessage.avatar]) &&
      self.hasOrganization == otherMessage.hasOrganization &&
      (!self.hasOrganization || [self.organization isEqual:otherMessage.organization]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasName) {
    hashCode = hashCode * 31 + [self.name hash];
  }
  [self.numberArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPhone *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  [self.emailArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactEmail *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  [self.addressArray enumerateObjectsUsingBlock:^(SSKProtoDataMessageContactPostalAddress *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasAvatar) {
    hashCode = hashCode * 31 + [self.avatar hash];
  }
  if (self.hasOrganization) {
    hashCode = hashCode * 31 + [self.organization hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoDataMessageContactName ()
@property (strong) NSString* givenName;
@property (strong) NSString* familyName;
@property (strong) NSString* prefix;
@property (strong) NSString* suffix;
@property (strong) NSString* middleName;
@property (strong) NSString* displayName;
@end

@implementation SSKProtoDataMessageContactName

- (BOOL) hasGivenName {
  return !!hasGivenName_;
}
- (void) setHasGivenName:(BOOL) _value_ {
  hasGivenName_ = !!_value_;
}
@synthesize givenName;
- (BOOL) hasFamilyName {
  return !!hasFamilyName_;
}
- (void) setHasFamilyName:(BOOL) _value_ {
  hasFamilyName_ = !!_value_;
}
@synthesize familyName;
- (BOOL) hasPrefix {
  return !!hasPrefix_;
}
- (void) setHasPrefix:(BOOL) _value_ {
  hasPrefix_ = !!_value_;
}
@synthesize prefix;
- (BOOL) hasSuffix {
  return !!hasSuffix_;
}
- (void) setHasSuffix:(BOOL) _value_ {
  hasSuffix_ = !!_value_;
}
@synthesize suffix;
- (BOOL) hasMiddleName {
  return !!hasMiddleName_;
}
- (void) setHasMiddleName:(BOOL) _value_ {
  hasMiddleName_ = !!_value_;
}
@synthesize middleName;
- (BOOL) hasDisplayName {
  return !!hasDisplayName_;
}
- (void) setHasDisplayName:(BOOL) _value_ {
  hasDisplayName_ = !!_value_;
}
@synthesize displayName;
- (instancetype) init {
  if ((self = [super init])) {
    self.givenName = @"";
    self.familyName = @"";
    self.prefix = @"";
    self.suffix = @"";
    self.middleName = @"";
    self.displayName = @"";
  }
  return self;
}
static SSKProtoDataMessageContactName* defaultSSKProtoDataMessageContactNameInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContactName class]) {
    defaultSSKProtoDataMessageContactNameInstance = [[SSKProtoDataMessageContactName alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactNameInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactNameInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasGivenName) {
    [output writeString:1 value:self.givenName];
  }
  if (self.hasFamilyName) {
    [output writeString:2 value:self.familyName];
  }
  if (self.hasPrefix) {
    [output writeString:3 value:self.prefix];
  }
  if (self.hasSuffix) {
    [output writeString:4 value:self.suffix];
  }
  if (self.hasMiddleName) {
    [output writeString:5 value:self.middleName];
  }
  if (self.hasDisplayName) {
    [output writeString:6 value:self.displayName];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasGivenName) {
    size_ += computeStringSize(1, self.givenName);
  }
  if (self.hasFamilyName) {
    size_ += computeStringSize(2, self.familyName);
  }
  if (self.hasPrefix) {
    size_ += computeStringSize(3, self.prefix);
  }
  if (self.hasSuffix) {
    size_ += computeStringSize(4, self.suffix);
  }
  if (self.hasMiddleName) {
    size_ += computeStringSize(5, self.middleName);
  }
  if (self.hasDisplayName) {
    size_ += computeStringSize(6, self.displayName);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContactName*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContactName*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactName*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContactName*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactName*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContactName*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactName*)[[[SSKProtoDataMessageContactName builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactNameBuilder*) builder {
  return [[SSKProtoDataMessageContactNameBuilder alloc] init];
}
+ (SSKProtoDataMessageContactNameBuilder*) builderWithPrototype:(SSKProtoDataMessageContactName*) prototype {
  return [[SSKProtoDataMessageContactName builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactNameBuilder*) builder {
  return [SSKProtoDataMessageContactName builder];
}
- (SSKProtoDataMessageContactNameBuilder*) toBuilder {
  return [SSKProtoDataMessageContactName builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasGivenName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"givenName", self.givenName];
  }
  if (self.hasFamilyName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"familyName", self.familyName];
  }
  if (self.hasPrefix) {
    [output appendFormat:@"%@%@: %@\n", indent, @"prefix", self.prefix];
  }
  if (self.hasSuffix) {
    [output appendFormat:@"%@%@: %@\n", indent, @"suffix", self.suffix];
  }
  if (self.hasMiddleName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"middleName", self.middleName];
  }
  if (self.hasDisplayName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"displayName", self.displayName];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasGivenName) {
    [dictionary setObject: self.givenName forKey: @"givenName"];
  }
  if (self.hasFamilyName) {
    [dictionary setObject: self.familyName forKey: @"familyName"];
  }
  if (self.hasPrefix) {
    [dictionary setObject: self.prefix forKey: @"prefix"];
  }
  if (self.hasSuffix) {
    [dictionary setObject: self.suffix forKey: @"suffix"];
  }
  if (self.hasMiddleName) {
    [dictionary setObject: self.middleName forKey: @"middleName"];
  }
  if (self.hasDisplayName) {
    [dictionary setObject: self.displayName forKey: @"displayName"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContactName class]]) {
    return NO;
  }
  SSKProtoDataMessageContactName *otherMessage = other;
  return
      self.hasGivenName == otherMessage.hasGivenName &&
      (!self.hasGivenName || [self.givenName isEqual:otherMessage.givenName]) &&
      self.hasFamilyName == otherMessage.hasFamilyName &&
      (!self.hasFamilyName || [self.familyName isEqual:otherMessage.familyName]) &&
      self.hasPrefix == otherMessage.hasPrefix &&
      (!self.hasPrefix || [self.prefix isEqual:otherMessage.prefix]) &&
      self.hasSuffix == otherMessage.hasSuffix &&
      (!self.hasSuffix || [self.suffix isEqual:otherMessage.suffix]) &&
      self.hasMiddleName == otherMessage.hasMiddleName &&
      (!self.hasMiddleName || [self.middleName isEqual:otherMessage.middleName]) &&
      self.hasDisplayName == otherMessage.hasDisplayName &&
      (!self.hasDisplayName || [self.displayName isEqual:otherMessage.displayName]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasGivenName) {
    hashCode = hashCode * 31 + [self.givenName hash];
  }
  if (self.hasFamilyName) {
    hashCode = hashCode * 31 + [self.familyName hash];
  }
  if (self.hasPrefix) {
    hashCode = hashCode * 31 + [self.prefix hash];
  }
  if (self.hasSuffix) {
    hashCode = hashCode * 31 + [self.suffix hash];
  }
  if (self.hasMiddleName) {
    hashCode = hashCode * 31 + [self.middleName hash];
  }
  if (self.hasDisplayName) {
    hashCode = hashCode * 31 + [self.displayName hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoDataMessageContactNameBuilder()
@property (strong) SSKProtoDataMessageContactName* resultName;
@end

@implementation SSKProtoDataMessageContactNameBuilder
@synthesize resultName;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultName = [[SSKProtoDataMessageContactName alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultName;
}
- (SSKProtoDataMessageContactNameBuilder*) clear {
  self.resultName = [[SSKProtoDataMessageContactName alloc] init];
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clone {
  return [SSKProtoDataMessageContactName builderWithPrototype:resultName];
}
- (SSKProtoDataMessageContactName*) defaultInstance {
  return [SSKProtoDataMessageContactName defaultInstance];
}
- (SSKProtoDataMessageContactName*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContactName*) buildPartial {
  SSKProtoDataMessageContactName* returnMe = resultName;
  self.resultName = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactNameBuilder*) mergeFrom:(SSKProtoDataMessageContactName*) other {
  if (other == [SSKProtoDataMessageContactName defaultInstance]) {
    return self;
  }
  if (other.hasGivenName) {
    [self setGivenName:other.givenName];
  }
  if (other.hasFamilyName) {
    [self setFamilyName:other.familyName];
  }
  if (other.hasPrefix) {
    [self setPrefix:other.prefix];
  }
  if (other.hasSuffix) {
    [self setSuffix:other.suffix];
  }
  if (other.hasMiddleName) {
    [self setMiddleName:other.middleName];
  }
  if (other.hasDisplayName) {
    [self setDisplayName:other.displayName];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactNameBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setGivenName:[input readString]];
        break;
      }
      case 18: {
        [self setFamilyName:[input readString]];
        break;
      }
      case 26: {
        [self setPrefix:[input readString]];
        break;
      }
      case 34: {
        [self setSuffix:[input readString]];
        break;
      }
      case 42: {
        [self setMiddleName:[input readString]];
        break;
      }
      case 50: {
        [self setDisplayName:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasGivenName {
  return resultName.hasGivenName;
}
- (NSString*) givenName {
  return resultName.givenName;
}
- (SSKProtoDataMessageContactNameBuilder*) setGivenName:(NSString*) value {
  resultName.hasGivenName = YES;
  resultName.givenName = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearGivenName {
  resultName.hasGivenName = NO;
  resultName.givenName = @"";
  return self;
}
- (BOOL) hasFamilyName {
  return resultName.hasFamilyName;
}
- (NSString*) familyName {
  return resultName.familyName;
}
- (SSKProtoDataMessageContactNameBuilder*) setFamilyName:(NSString*) value {
  resultName.hasFamilyName = YES;
  resultName.familyName = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearFamilyName {
  resultName.hasFamilyName = NO;
  resultName.familyName = @"";
  return self;
}
- (BOOL) hasPrefix {
  return resultName.hasPrefix;
}
- (NSString*) prefix {
  return resultName.prefix;
}
- (SSKProtoDataMessageContactNameBuilder*) setPrefix:(NSString*) value {
  resultName.hasPrefix = YES;
  resultName.prefix = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearPrefix {
  resultName.hasPrefix = NO;
  resultName.prefix = @"";
  return self;
}
- (BOOL) hasSuffix {
  return resultName.hasSuffix;
}
- (NSString*) suffix {
  return resultName.suffix;
}
- (SSKProtoDataMessageContactNameBuilder*) setSuffix:(NSString*) value {
  resultName.hasSuffix = YES;
  resultName.suffix = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearSuffix {
  resultName.hasSuffix = NO;
  resultName.suffix = @"";
  return self;
}
- (BOOL) hasMiddleName {
  return resultName.hasMiddleName;
}
- (NSString*) middleName {
  return resultName.middleName;
}
- (SSKProtoDataMessageContactNameBuilder*) setMiddleName:(NSString*) value {
  resultName.hasMiddleName = YES;
  resultName.middleName = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearMiddleName {
  resultName.hasMiddleName = NO;
  resultName.middleName = @"";
  return self;
}
- (BOOL) hasDisplayName {
  return resultName.hasDisplayName;
}
- (NSString*) displayName {
  return resultName.displayName;
}
- (SSKProtoDataMessageContactNameBuilder*) setDisplayName:(NSString*) value {
  resultName.hasDisplayName = YES;
  resultName.displayName = value;
  return self;
}
- (SSKProtoDataMessageContactNameBuilder*) clearDisplayName {
  resultName.hasDisplayName = NO;
  resultName.displayName = @"";
  return self;
}
@end

@interface SSKProtoDataMessageContactPhone ()
@property (strong) NSString* value;
@property SSKProtoDataMessageContactPhoneType type;
@property (strong) NSString* label;
@end

@implementation SSKProtoDataMessageContactPhone

- (BOOL) hasValue {
  return !!hasValue_;
}
- (void) setHasValue:(BOOL) _value_ {
  hasValue_ = !!_value_;
}
@synthesize value;
- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (BOOL) hasLabel {
  return !!hasLabel_;
}
- (void) setHasLabel:(BOOL) _value_ {
  hasLabel_ = !!_value_;
}
@synthesize label;
- (instancetype) init {
  if ((self = [super init])) {
    self.value = @"";
    self.type = SSKProtoDataMessageContactPhoneTypeHome;
    self.label = @"";
  }
  return self;
}
static SSKProtoDataMessageContactPhone* defaultSSKProtoDataMessageContactPhoneInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContactPhone class]) {
    defaultSSKProtoDataMessageContactPhoneInstance = [[SSKProtoDataMessageContactPhone alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactPhoneInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactPhoneInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasValue) {
    [output writeString:1 value:self.value];
  }
  if (self.hasType) {
    [output writeEnum:2 value:self.type];
  }
  if (self.hasLabel) {
    [output writeString:3 value:self.label];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasValue) {
    size_ += computeStringSize(1, self.value);
  }
  if (self.hasType) {
    size_ += computeEnumSize(2, self.type);
  }
  if (self.hasLabel) {
    size_ += computeStringSize(3, self.label);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContactPhone*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContactPhone*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPhone*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContactPhone*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPhone*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContactPhone*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPhone*)[[[SSKProtoDataMessageContactPhone builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPhoneBuilder*) builder {
  return [[SSKProtoDataMessageContactPhoneBuilder alloc] init];
}
+ (SSKProtoDataMessageContactPhoneBuilder*) builderWithPrototype:(SSKProtoDataMessageContactPhone*) prototype {
  return [[SSKProtoDataMessageContactPhone builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactPhoneBuilder*) builder {
  return [SSKProtoDataMessageContactPhone builder];
}
- (SSKProtoDataMessageContactPhoneBuilder*) toBuilder {
  return [SSKProtoDataMessageContactPhone builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasValue) {
    [output appendFormat:@"%@%@: %@\n", indent, @"value", self.value];
  }
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoDataMessageContactPhoneType(self.type)];
  }
  if (self.hasLabel) {
    [output appendFormat:@"%@%@: %@\n", indent, @"label", self.label];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasValue) {
    [dictionary setObject: self.value forKey: @"value"];
  }
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  if (self.hasLabel) {
    [dictionary setObject: self.label forKey: @"label"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContactPhone class]]) {
    return NO;
  }
  SSKProtoDataMessageContactPhone *otherMessage = other;
  return
      self.hasValue == otherMessage.hasValue &&
      (!self.hasValue || [self.value isEqual:otherMessage.value]) &&
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      self.hasLabel == otherMessage.hasLabel &&
      (!self.hasLabel || [self.label isEqual:otherMessage.label]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasValue) {
    hashCode = hashCode * 31 + [self.value hash];
  }
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  if (self.hasLabel) {
    hashCode = hashCode * 31 + [self.label hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoDataMessageContactPhoneTypeIsValidValue(SSKProtoDataMessageContactPhoneType value) {
  switch (value) {
    case SSKProtoDataMessageContactPhoneTypeHome:
    case SSKProtoDataMessageContactPhoneTypeMobile:
    case SSKProtoDataMessageContactPhoneTypeWork:
    case SSKProtoDataMessageContactPhoneTypeCustom:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoDataMessageContactPhoneType(SSKProtoDataMessageContactPhoneType value) {
  switch (value) {
    case SSKProtoDataMessageContactPhoneTypeHome:
      return @"SSKProtoDataMessageContactPhoneTypeHome";
    case SSKProtoDataMessageContactPhoneTypeMobile:
      return @"SSKProtoDataMessageContactPhoneTypeMobile";
    case SSKProtoDataMessageContactPhoneTypeWork:
      return @"SSKProtoDataMessageContactPhoneTypeWork";
    case SSKProtoDataMessageContactPhoneTypeCustom:
      return @"SSKProtoDataMessageContactPhoneTypeCustom";
    default:
      return nil;
  }
}

@interface SSKProtoDataMessageContactPhoneBuilder()
@property (strong) SSKProtoDataMessageContactPhone* resultPhone;
@end

@implementation SSKProtoDataMessageContactPhoneBuilder
@synthesize resultPhone;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultPhone = [[SSKProtoDataMessageContactPhone alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultPhone;
}
- (SSKProtoDataMessageContactPhoneBuilder*) clear {
  self.resultPhone = [[SSKProtoDataMessageContactPhone alloc] init];
  return self;
}
- (SSKProtoDataMessageContactPhoneBuilder*) clone {
  return [SSKProtoDataMessageContactPhone builderWithPrototype:resultPhone];
}
- (SSKProtoDataMessageContactPhone*) defaultInstance {
  return [SSKProtoDataMessageContactPhone defaultInstance];
}
- (SSKProtoDataMessageContactPhone*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContactPhone*) buildPartial {
  SSKProtoDataMessageContactPhone* returnMe = resultPhone;
  self.resultPhone = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactPhoneBuilder*) mergeFrom:(SSKProtoDataMessageContactPhone*) other {
  if (other == [SSKProtoDataMessageContactPhone defaultInstance]) {
    return self;
  }
  if (other.hasValue) {
    [self setValue:other.value];
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.hasLabel) {
    [self setLabel:other.label];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactPhoneBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactPhoneBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setValue:[input readString]];
        break;
      }
      case 16: {
        SSKProtoDataMessageContactPhoneType value = (SSKProtoDataMessageContactPhoneType)[input readEnum];
        if (SSKProtoDataMessageContactPhoneTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:2 value:value];
        }
        break;
      }
      case 26: {
        [self setLabel:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasValue {
  return resultPhone.hasValue;
}
- (NSString*) value {
  return resultPhone.value;
}
- (SSKProtoDataMessageContactPhoneBuilder*) setValue:(NSString*) value {
  resultPhone.hasValue = YES;
  resultPhone.value = value;
  return self;
}
- (SSKProtoDataMessageContactPhoneBuilder*) clearValue {
  resultPhone.hasValue = NO;
  resultPhone.value = @"";
  return self;
}
- (BOOL) hasType {
  return resultPhone.hasType;
}
- (SSKProtoDataMessageContactPhoneType) type {
  return resultPhone.type;
}
- (SSKProtoDataMessageContactPhoneBuilder*) setType:(SSKProtoDataMessageContactPhoneType) value {
  resultPhone.hasType = YES;
  resultPhone.type = value;
  return self;
}
- (SSKProtoDataMessageContactPhoneBuilder*) clearType {
  resultPhone.hasType = NO;
  resultPhone.type = SSKProtoDataMessageContactPhoneTypeHome;
  return self;
}
- (BOOL) hasLabel {
  return resultPhone.hasLabel;
}
- (NSString*) label {
  return resultPhone.label;
}
- (SSKProtoDataMessageContactPhoneBuilder*) setLabel:(NSString*) value {
  resultPhone.hasLabel = YES;
  resultPhone.label = value;
  return self;
}
- (SSKProtoDataMessageContactPhoneBuilder*) clearLabel {
  resultPhone.hasLabel = NO;
  resultPhone.label = @"";
  return self;
}
@end

@interface SSKProtoDataMessageContactEmail ()
@property (strong) NSString* value;
@property SSKProtoDataMessageContactEmailType type;
@property (strong) NSString* label;
@end

@implementation SSKProtoDataMessageContactEmail

- (BOOL) hasValue {
  return !!hasValue_;
}
- (void) setHasValue:(BOOL) _value_ {
  hasValue_ = !!_value_;
}
@synthesize value;
- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (BOOL) hasLabel {
  return !!hasLabel_;
}
- (void) setHasLabel:(BOOL) _value_ {
  hasLabel_ = !!_value_;
}
@synthesize label;
- (instancetype) init {
  if ((self = [super init])) {
    self.value = @"";
    self.type = SSKProtoDataMessageContactEmailTypeHome;
    self.label = @"";
  }
  return self;
}
static SSKProtoDataMessageContactEmail* defaultSSKProtoDataMessageContactEmailInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContactEmail class]) {
    defaultSSKProtoDataMessageContactEmailInstance = [[SSKProtoDataMessageContactEmail alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactEmailInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactEmailInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasValue) {
    [output writeString:1 value:self.value];
  }
  if (self.hasType) {
    [output writeEnum:2 value:self.type];
  }
  if (self.hasLabel) {
    [output writeString:3 value:self.label];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasValue) {
    size_ += computeStringSize(1, self.value);
  }
  if (self.hasType) {
    size_ += computeEnumSize(2, self.type);
  }
  if (self.hasLabel) {
    size_ += computeStringSize(3, self.label);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContactEmail*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContactEmail*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactEmail*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContactEmail*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactEmail*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContactEmail*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactEmail*)[[[SSKProtoDataMessageContactEmail builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactEmailBuilder*) builder {
  return [[SSKProtoDataMessageContactEmailBuilder alloc] init];
}
+ (SSKProtoDataMessageContactEmailBuilder*) builderWithPrototype:(SSKProtoDataMessageContactEmail*) prototype {
  return [[SSKProtoDataMessageContactEmail builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactEmailBuilder*) builder {
  return [SSKProtoDataMessageContactEmail builder];
}
- (SSKProtoDataMessageContactEmailBuilder*) toBuilder {
  return [SSKProtoDataMessageContactEmail builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasValue) {
    [output appendFormat:@"%@%@: %@\n", indent, @"value", self.value];
  }
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoDataMessageContactEmailType(self.type)];
  }
  if (self.hasLabel) {
    [output appendFormat:@"%@%@: %@\n", indent, @"label", self.label];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasValue) {
    [dictionary setObject: self.value forKey: @"value"];
  }
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  if (self.hasLabel) {
    [dictionary setObject: self.label forKey: @"label"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContactEmail class]]) {
    return NO;
  }
  SSKProtoDataMessageContactEmail *otherMessage = other;
  return
      self.hasValue == otherMessage.hasValue &&
      (!self.hasValue || [self.value isEqual:otherMessage.value]) &&
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      self.hasLabel == otherMessage.hasLabel &&
      (!self.hasLabel || [self.label isEqual:otherMessage.label]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasValue) {
    hashCode = hashCode * 31 + [self.value hash];
  }
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  if (self.hasLabel) {
    hashCode = hashCode * 31 + [self.label hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoDataMessageContactEmailTypeIsValidValue(SSKProtoDataMessageContactEmailType value) {
  switch (value) {
    case SSKProtoDataMessageContactEmailTypeHome:
    case SSKProtoDataMessageContactEmailTypeMobile:
    case SSKProtoDataMessageContactEmailTypeWork:
    case SSKProtoDataMessageContactEmailTypeCustom:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoDataMessageContactEmailType(SSKProtoDataMessageContactEmailType value) {
  switch (value) {
    case SSKProtoDataMessageContactEmailTypeHome:
      return @"SSKProtoDataMessageContactEmailTypeHome";
    case SSKProtoDataMessageContactEmailTypeMobile:
      return @"SSKProtoDataMessageContactEmailTypeMobile";
    case SSKProtoDataMessageContactEmailTypeWork:
      return @"SSKProtoDataMessageContactEmailTypeWork";
    case SSKProtoDataMessageContactEmailTypeCustom:
      return @"SSKProtoDataMessageContactEmailTypeCustom";
    default:
      return nil;
  }
}

@interface SSKProtoDataMessageContactEmailBuilder()
@property (strong) SSKProtoDataMessageContactEmail* resultEmail;
@end

@implementation SSKProtoDataMessageContactEmailBuilder
@synthesize resultEmail;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultEmail = [[SSKProtoDataMessageContactEmail alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultEmail;
}
- (SSKProtoDataMessageContactEmailBuilder*) clear {
  self.resultEmail = [[SSKProtoDataMessageContactEmail alloc] init];
  return self;
}
- (SSKProtoDataMessageContactEmailBuilder*) clone {
  return [SSKProtoDataMessageContactEmail builderWithPrototype:resultEmail];
}
- (SSKProtoDataMessageContactEmail*) defaultInstance {
  return [SSKProtoDataMessageContactEmail defaultInstance];
}
- (SSKProtoDataMessageContactEmail*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContactEmail*) buildPartial {
  SSKProtoDataMessageContactEmail* returnMe = resultEmail;
  self.resultEmail = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactEmailBuilder*) mergeFrom:(SSKProtoDataMessageContactEmail*) other {
  if (other == [SSKProtoDataMessageContactEmail defaultInstance]) {
    return self;
  }
  if (other.hasValue) {
    [self setValue:other.value];
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.hasLabel) {
    [self setLabel:other.label];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactEmailBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactEmailBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setValue:[input readString]];
        break;
      }
      case 16: {
        SSKProtoDataMessageContactEmailType value = (SSKProtoDataMessageContactEmailType)[input readEnum];
        if (SSKProtoDataMessageContactEmailTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:2 value:value];
        }
        break;
      }
      case 26: {
        [self setLabel:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasValue {
  return resultEmail.hasValue;
}
- (NSString*) value {
  return resultEmail.value;
}
- (SSKProtoDataMessageContactEmailBuilder*) setValue:(NSString*) value {
  resultEmail.hasValue = YES;
  resultEmail.value = value;
  return self;
}
- (SSKProtoDataMessageContactEmailBuilder*) clearValue {
  resultEmail.hasValue = NO;
  resultEmail.value = @"";
  return self;
}
- (BOOL) hasType {
  return resultEmail.hasType;
}
- (SSKProtoDataMessageContactEmailType) type {
  return resultEmail.type;
}
- (SSKProtoDataMessageContactEmailBuilder*) setType:(SSKProtoDataMessageContactEmailType) value {
  resultEmail.hasType = YES;
  resultEmail.type = value;
  return self;
}
- (SSKProtoDataMessageContactEmailBuilder*) clearType {
  resultEmail.hasType = NO;
  resultEmail.type = SSKProtoDataMessageContactEmailTypeHome;
  return self;
}
- (BOOL) hasLabel {
  return resultEmail.hasLabel;
}
- (NSString*) label {
  return resultEmail.label;
}
- (SSKProtoDataMessageContactEmailBuilder*) setLabel:(NSString*) value {
  resultEmail.hasLabel = YES;
  resultEmail.label = value;
  return self;
}
- (SSKProtoDataMessageContactEmailBuilder*) clearLabel {
  resultEmail.hasLabel = NO;
  resultEmail.label = @"";
  return self;
}
@end

@interface SSKProtoDataMessageContactPostalAddress ()
@property SSKProtoDataMessageContactPostalAddressType type;
@property (strong) NSString* label;
@property (strong) NSString* street;
@property (strong) NSString* pobox;
@property (strong) NSString* neighborhood;
@property (strong) NSString* city;
@property (strong) NSString* region;
@property (strong) NSString* postcode;
@property (strong) NSString* country;
@end

@implementation SSKProtoDataMessageContactPostalAddress

- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (BOOL) hasLabel {
  return !!hasLabel_;
}
- (void) setHasLabel:(BOOL) _value_ {
  hasLabel_ = !!_value_;
}
@synthesize label;
- (BOOL) hasStreet {
  return !!hasStreet_;
}
- (void) setHasStreet:(BOOL) _value_ {
  hasStreet_ = !!_value_;
}
@synthesize street;
- (BOOL) hasPobox {
  return !!hasPobox_;
}
- (void) setHasPobox:(BOOL) _value_ {
  hasPobox_ = !!_value_;
}
@synthesize pobox;
- (BOOL) hasNeighborhood {
  return !!hasNeighborhood_;
}
- (void) setHasNeighborhood:(BOOL) _value_ {
  hasNeighborhood_ = !!_value_;
}
@synthesize neighborhood;
- (BOOL) hasCity {
  return !!hasCity_;
}
- (void) setHasCity:(BOOL) _value_ {
  hasCity_ = !!_value_;
}
@synthesize city;
- (BOOL) hasRegion {
  return !!hasRegion_;
}
- (void) setHasRegion:(BOOL) _value_ {
  hasRegion_ = !!_value_;
}
@synthesize region;
- (BOOL) hasPostcode {
  return !!hasPostcode_;
}
- (void) setHasPostcode:(BOOL) _value_ {
  hasPostcode_ = !!_value_;
}
@synthesize postcode;
- (BOOL) hasCountry {
  return !!hasCountry_;
}
- (void) setHasCountry:(BOOL) _value_ {
  hasCountry_ = !!_value_;
}
@synthesize country;
- (instancetype) init {
  if ((self = [super init])) {
    self.type = SSKProtoDataMessageContactPostalAddressTypeHome;
    self.label = @"";
    self.street = @"";
    self.pobox = @"";
    self.neighborhood = @"";
    self.city = @"";
    self.region = @"";
    self.postcode = @"";
    self.country = @"";
  }
  return self;
}
static SSKProtoDataMessageContactPostalAddress* defaultSSKProtoDataMessageContactPostalAddressInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContactPostalAddress class]) {
    defaultSSKProtoDataMessageContactPostalAddressInstance = [[SSKProtoDataMessageContactPostalAddress alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactPostalAddressInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactPostalAddressInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasType) {
    [output writeEnum:1 value:self.type];
  }
  if (self.hasLabel) {
    [output writeString:2 value:self.label];
  }
  if (self.hasStreet) {
    [output writeString:3 value:self.street];
  }
  if (self.hasPobox) {
    [output writeString:4 value:self.pobox];
  }
  if (self.hasNeighborhood) {
    [output writeString:5 value:self.neighborhood];
  }
  if (self.hasCity) {
    [output writeString:6 value:self.city];
  }
  if (self.hasRegion) {
    [output writeString:7 value:self.region];
  }
  if (self.hasPostcode) {
    [output writeString:8 value:self.postcode];
  }
  if (self.hasCountry) {
    [output writeString:9 value:self.country];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasType) {
    size_ += computeEnumSize(1, self.type);
  }
  if (self.hasLabel) {
    size_ += computeStringSize(2, self.label);
  }
  if (self.hasStreet) {
    size_ += computeStringSize(3, self.street);
  }
  if (self.hasPobox) {
    size_ += computeStringSize(4, self.pobox);
  }
  if (self.hasNeighborhood) {
    size_ += computeStringSize(5, self.neighborhood);
  }
  if (self.hasCity) {
    size_ += computeStringSize(6, self.city);
  }
  if (self.hasRegion) {
    size_ += computeStringSize(7, self.region);
  }
  if (self.hasPostcode) {
    size_ += computeStringSize(8, self.postcode);
  }
  if (self.hasCountry) {
    size_ += computeStringSize(9, self.country);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContactPostalAddress*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactPostalAddress*)[[[SSKProtoDataMessageContactPostalAddress builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactPostalAddressBuilder*) builder {
  return [[SSKProtoDataMessageContactPostalAddressBuilder alloc] init];
}
+ (SSKProtoDataMessageContactPostalAddressBuilder*) builderWithPrototype:(SSKProtoDataMessageContactPostalAddress*) prototype {
  return [[SSKProtoDataMessageContactPostalAddress builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) builder {
  return [SSKProtoDataMessageContactPostalAddress builder];
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) toBuilder {
  return [SSKProtoDataMessageContactPostalAddress builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoDataMessageContactPostalAddressType(self.type)];
  }
  if (self.hasLabel) {
    [output appendFormat:@"%@%@: %@\n", indent, @"label", self.label];
  }
  if (self.hasStreet) {
    [output appendFormat:@"%@%@: %@\n", indent, @"street", self.street];
  }
  if (self.hasPobox) {
    [output appendFormat:@"%@%@: %@\n", indent, @"pobox", self.pobox];
  }
  if (self.hasNeighborhood) {
    [output appendFormat:@"%@%@: %@\n", indent, @"neighborhood", self.neighborhood];
  }
  if (self.hasCity) {
    [output appendFormat:@"%@%@: %@\n", indent, @"city", self.city];
  }
  if (self.hasRegion) {
    [output appendFormat:@"%@%@: %@\n", indent, @"region", self.region];
  }
  if (self.hasPostcode) {
    [output appendFormat:@"%@%@: %@\n", indent, @"postcode", self.postcode];
  }
  if (self.hasCountry) {
    [output appendFormat:@"%@%@: %@\n", indent, @"country", self.country];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  if (self.hasLabel) {
    [dictionary setObject: self.label forKey: @"label"];
  }
  if (self.hasStreet) {
    [dictionary setObject: self.street forKey: @"street"];
  }
  if (self.hasPobox) {
    [dictionary setObject: self.pobox forKey: @"pobox"];
  }
  if (self.hasNeighborhood) {
    [dictionary setObject: self.neighborhood forKey: @"neighborhood"];
  }
  if (self.hasCity) {
    [dictionary setObject: self.city forKey: @"city"];
  }
  if (self.hasRegion) {
    [dictionary setObject: self.region forKey: @"region"];
  }
  if (self.hasPostcode) {
    [dictionary setObject: self.postcode forKey: @"postcode"];
  }
  if (self.hasCountry) {
    [dictionary setObject: self.country forKey: @"country"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContactPostalAddress class]]) {
    return NO;
  }
  SSKProtoDataMessageContactPostalAddress *otherMessage = other;
  return
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      self.hasLabel == otherMessage.hasLabel &&
      (!self.hasLabel || [self.label isEqual:otherMessage.label]) &&
      self.hasStreet == otherMessage.hasStreet &&
      (!self.hasStreet || [self.street isEqual:otherMessage.street]) &&
      self.hasPobox == otherMessage.hasPobox &&
      (!self.hasPobox || [self.pobox isEqual:otherMessage.pobox]) &&
      self.hasNeighborhood == otherMessage.hasNeighborhood &&
      (!self.hasNeighborhood || [self.neighborhood isEqual:otherMessage.neighborhood]) &&
      self.hasCity == otherMessage.hasCity &&
      (!self.hasCity || [self.city isEqual:otherMessage.city]) &&
      self.hasRegion == otherMessage.hasRegion &&
      (!self.hasRegion || [self.region isEqual:otherMessage.region]) &&
      self.hasPostcode == otherMessage.hasPostcode &&
      (!self.hasPostcode || [self.postcode isEqual:otherMessage.postcode]) &&
      self.hasCountry == otherMessage.hasCountry &&
      (!self.hasCountry || [self.country isEqual:otherMessage.country]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  if (self.hasLabel) {
    hashCode = hashCode * 31 + [self.label hash];
  }
  if (self.hasStreet) {
    hashCode = hashCode * 31 + [self.street hash];
  }
  if (self.hasPobox) {
    hashCode = hashCode * 31 + [self.pobox hash];
  }
  if (self.hasNeighborhood) {
    hashCode = hashCode * 31 + [self.neighborhood hash];
  }
  if (self.hasCity) {
    hashCode = hashCode * 31 + [self.city hash];
  }
  if (self.hasRegion) {
    hashCode = hashCode * 31 + [self.region hash];
  }
  if (self.hasPostcode) {
    hashCode = hashCode * 31 + [self.postcode hash];
  }
  if (self.hasCountry) {
    hashCode = hashCode * 31 + [self.country hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoDataMessageContactPostalAddressTypeIsValidValue(SSKProtoDataMessageContactPostalAddressType value) {
  switch (value) {
    case SSKProtoDataMessageContactPostalAddressTypeHome:
    case SSKProtoDataMessageContactPostalAddressTypeWork:
    case SSKProtoDataMessageContactPostalAddressTypeCustom:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoDataMessageContactPostalAddressType(SSKProtoDataMessageContactPostalAddressType value) {
  switch (value) {
    case SSKProtoDataMessageContactPostalAddressTypeHome:
      return @"SSKProtoDataMessageContactPostalAddressTypeHome";
    case SSKProtoDataMessageContactPostalAddressTypeWork:
      return @"SSKProtoDataMessageContactPostalAddressTypeWork";
    case SSKProtoDataMessageContactPostalAddressTypeCustom:
      return @"SSKProtoDataMessageContactPostalAddressTypeCustom";
    default:
      return nil;
  }
}

@interface SSKProtoDataMessageContactPostalAddressBuilder()
@property (strong) SSKProtoDataMessageContactPostalAddress* resultPostalAddress;
@end

@implementation SSKProtoDataMessageContactPostalAddressBuilder
@synthesize resultPostalAddress;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultPostalAddress = [[SSKProtoDataMessageContactPostalAddress alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultPostalAddress;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clear {
  self.resultPostalAddress = [[SSKProtoDataMessageContactPostalAddress alloc] init];
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clone {
  return [SSKProtoDataMessageContactPostalAddress builderWithPrototype:resultPostalAddress];
}
- (SSKProtoDataMessageContactPostalAddress*) defaultInstance {
  return [SSKProtoDataMessageContactPostalAddress defaultInstance];
}
- (SSKProtoDataMessageContactPostalAddress*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContactPostalAddress*) buildPartial {
  SSKProtoDataMessageContactPostalAddress* returnMe = resultPostalAddress;
  self.resultPostalAddress = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFrom:(SSKProtoDataMessageContactPostalAddress*) other {
  if (other == [SSKProtoDataMessageContactPostalAddress defaultInstance]) {
    return self;
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.hasLabel) {
    [self setLabel:other.label];
  }
  if (other.hasStreet) {
    [self setStreet:other.street];
  }
  if (other.hasPobox) {
    [self setPobox:other.pobox];
  }
  if (other.hasNeighborhood) {
    [self setNeighborhood:other.neighborhood];
  }
  if (other.hasCity) {
    [self setCity:other.city];
  }
  if (other.hasRegion) {
    [self setRegion:other.region];
  }
  if (other.hasPostcode) {
    [self setPostcode:other.postcode];
  }
  if (other.hasCountry) {
    [self setCountry:other.country];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        SSKProtoDataMessageContactPostalAddressType value = (SSKProtoDataMessageContactPostalAddressType)[input readEnum];
        if (SSKProtoDataMessageContactPostalAddressTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:1 value:value];
        }
        break;
      }
      case 18: {
        [self setLabel:[input readString]];
        break;
      }
      case 26: {
        [self setStreet:[input readString]];
        break;
      }
      case 34: {
        [self setPobox:[input readString]];
        break;
      }
      case 42: {
        [self setNeighborhood:[input readString]];
        break;
      }
      case 50: {
        [self setCity:[input readString]];
        break;
      }
      case 58: {
        [self setRegion:[input readString]];
        break;
      }
      case 66: {
        [self setPostcode:[input readString]];
        break;
      }
      case 74: {
        [self setCountry:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasType {
  return resultPostalAddress.hasType;
}
- (SSKProtoDataMessageContactPostalAddressType) type {
  return resultPostalAddress.type;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setType:(SSKProtoDataMessageContactPostalAddressType) value {
  resultPostalAddress.hasType = YES;
  resultPostalAddress.type = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearType {
  resultPostalAddress.hasType = NO;
  resultPostalAddress.type = SSKProtoDataMessageContactPostalAddressTypeHome;
  return self;
}
- (BOOL) hasLabel {
  return resultPostalAddress.hasLabel;
}
- (NSString*) label {
  return resultPostalAddress.label;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setLabel:(NSString*) value {
  resultPostalAddress.hasLabel = YES;
  resultPostalAddress.label = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearLabel {
  resultPostalAddress.hasLabel = NO;
  resultPostalAddress.label = @"";
  return self;
}
- (BOOL) hasStreet {
  return resultPostalAddress.hasStreet;
}
- (NSString*) street {
  return resultPostalAddress.street;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setStreet:(NSString*) value {
  resultPostalAddress.hasStreet = YES;
  resultPostalAddress.street = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearStreet {
  resultPostalAddress.hasStreet = NO;
  resultPostalAddress.street = @"";
  return self;
}
- (BOOL) hasPobox {
  return resultPostalAddress.hasPobox;
}
- (NSString*) pobox {
  return resultPostalAddress.pobox;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setPobox:(NSString*) value {
  resultPostalAddress.hasPobox = YES;
  resultPostalAddress.pobox = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearPobox {
  resultPostalAddress.hasPobox = NO;
  resultPostalAddress.pobox = @"";
  return self;
}
- (BOOL) hasNeighborhood {
  return resultPostalAddress.hasNeighborhood;
}
- (NSString*) neighborhood {
  return resultPostalAddress.neighborhood;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setNeighborhood:(NSString*) value {
  resultPostalAddress.hasNeighborhood = YES;
  resultPostalAddress.neighborhood = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearNeighborhood {
  resultPostalAddress.hasNeighborhood = NO;
  resultPostalAddress.neighborhood = @"";
  return self;
}
- (BOOL) hasCity {
  return resultPostalAddress.hasCity;
}
- (NSString*) city {
  return resultPostalAddress.city;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setCity:(NSString*) value {
  resultPostalAddress.hasCity = YES;
  resultPostalAddress.city = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearCity {
  resultPostalAddress.hasCity = NO;
  resultPostalAddress.city = @"";
  return self;
}
- (BOOL) hasRegion {
  return resultPostalAddress.hasRegion;
}
- (NSString*) region {
  return resultPostalAddress.region;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setRegion:(NSString*) value {
  resultPostalAddress.hasRegion = YES;
  resultPostalAddress.region = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearRegion {
  resultPostalAddress.hasRegion = NO;
  resultPostalAddress.region = @"";
  return self;
}
- (BOOL) hasPostcode {
  return resultPostalAddress.hasPostcode;
}
- (NSString*) postcode {
  return resultPostalAddress.postcode;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setPostcode:(NSString*) value {
  resultPostalAddress.hasPostcode = YES;
  resultPostalAddress.postcode = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearPostcode {
  resultPostalAddress.hasPostcode = NO;
  resultPostalAddress.postcode = @"";
  return self;
}
- (BOOL) hasCountry {
  return resultPostalAddress.hasCountry;
}
- (NSString*) country {
  return resultPostalAddress.country;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) setCountry:(NSString*) value {
  resultPostalAddress.hasCountry = YES;
  resultPostalAddress.country = value;
  return self;
}
- (SSKProtoDataMessageContactPostalAddressBuilder*) clearCountry {
  resultPostalAddress.hasCountry = NO;
  resultPostalAddress.country = @"";
  return self;
}
@end

@interface SSKProtoDataMessageContactAvatar ()
@property (strong) SSKProtoAttachmentPointer* avatar;
@property BOOL isProfile;
@end

@implementation SSKProtoDataMessageContactAvatar

- (BOOL) hasAvatar {
  return !!hasAvatar_;
}
- (void) setHasAvatar:(BOOL) _value_ {
  hasAvatar_ = !!_value_;
}
@synthesize avatar;
- (BOOL) hasIsProfile {
  return !!hasIsProfile_;
}
- (void) setHasIsProfile:(BOOL) _value_ {
  hasIsProfile_ = !!_value_;
}
- (BOOL) isProfile {
  return !!isProfile_;
}
- (void) setIsProfile:(BOOL) _value_ {
  isProfile_ = !!_value_;
}
- (instancetype) init {
  if ((self = [super init])) {
    self.avatar = [SSKProtoAttachmentPointer defaultInstance];
    self.isProfile = NO;
  }
  return self;
}
static SSKProtoDataMessageContactAvatar* defaultSSKProtoDataMessageContactAvatarInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoDataMessageContactAvatar class]) {
    defaultSSKProtoDataMessageContactAvatarInstance = [[SSKProtoDataMessageContactAvatar alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactAvatarInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoDataMessageContactAvatarInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasAvatar) {
    [output writeMessage:1 value:self.avatar];
  }
  if (self.hasIsProfile) {
    [output writeBool:2 value:self.isProfile];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasAvatar) {
    size_ += computeMessageSize(1, self.avatar);
  }
  if (self.hasIsProfile) {
    size_ += computeBoolSize(2, self.isProfile);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoDataMessageContactAvatar*) parseFromData:(NSData*) data {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromData:data] build];
}
+ (SSKProtoDataMessageContactAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactAvatar*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromInputStream:input] build];
}
+ (SSKProtoDataMessageContactAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoDataMessageContactAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoDataMessageContactAvatar*)[[[SSKProtoDataMessageContactAvatar builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoDataMessageContactAvatarBuilder*) builder {
  return [[SSKProtoDataMessageContactAvatarBuilder alloc] init];
}
+ (SSKProtoDataMessageContactAvatarBuilder*) builderWithPrototype:(SSKProtoDataMessageContactAvatar*) prototype {
  return [[SSKProtoDataMessageContactAvatar builder] mergeFrom:prototype];
}
- (SSKProtoDataMessageContactAvatarBuilder*) builder {
  return [SSKProtoDataMessageContactAvatar builder];
}
- (SSKProtoDataMessageContactAvatarBuilder*) toBuilder {
  return [SSKProtoDataMessageContactAvatar builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasAvatar) {
    [output appendFormat:@"%@%@ {\n", indent, @"avatar"];
    [self.avatar writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasIsProfile) {
    [output appendFormat:@"%@%@: %@\n", indent, @"isProfile", [NSNumber numberWithBool:self.isProfile]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasAvatar) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.avatar storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"avatar"];
  }
  if (self.hasIsProfile) {
    [dictionary setObject: [NSNumber numberWithBool:self.isProfile] forKey: @"isProfile"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoDataMessageContactAvatar class]]) {
    return NO;
  }
  SSKProtoDataMessageContactAvatar *otherMessage = other;
  return
      self.hasAvatar == otherMessage.hasAvatar &&
      (!self.hasAvatar || [self.avatar isEqual:otherMessage.avatar]) &&
      self.hasIsProfile == otherMessage.hasIsProfile &&
      (!self.hasIsProfile || self.isProfile == otherMessage.isProfile) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasAvatar) {
    hashCode = hashCode * 31 + [self.avatar hash];
  }
  if (self.hasIsProfile) {
    hashCode = hashCode * 31 + [[NSNumber numberWithBool:self.isProfile] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoDataMessageContactAvatarBuilder()
@property (strong) SSKProtoDataMessageContactAvatar* resultAvatar;
@end

@implementation SSKProtoDataMessageContactAvatarBuilder
@synthesize resultAvatar;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultAvatar = [[SSKProtoDataMessageContactAvatar alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultAvatar;
}
- (SSKProtoDataMessageContactAvatarBuilder*) clear {
  self.resultAvatar = [[SSKProtoDataMessageContactAvatar alloc] init];
  return self;
}
- (SSKProtoDataMessageContactAvatarBuilder*) clone {
  return [SSKProtoDataMessageContactAvatar builderWithPrototype:resultAvatar];
}
- (SSKProtoDataMessageContactAvatar*) defaultInstance {
  return [SSKProtoDataMessageContactAvatar defaultInstance];
}
- (SSKProtoDataMessageContactAvatar*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContactAvatar*) buildPartial {
  SSKProtoDataMessageContactAvatar* returnMe = resultAvatar;
  self.resultAvatar = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactAvatarBuilder*) mergeFrom:(SSKProtoDataMessageContactAvatar*) other {
  if (other == [SSKProtoDataMessageContactAvatar defaultInstance]) {
    return self;
  }
  if (other.hasAvatar) {
    [self mergeAvatar:other.avatar];
  }
  if (other.hasIsProfile) {
    [self setIsProfile:other.isProfile];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        if (self.hasAvatar) {
          [subBuilder mergeFrom:self.avatar];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAvatar:[subBuilder buildPartial]];
        break;
      }
      case 16: {
        [self setIsProfile:[input readBool]];
        break;
      }
    }
  }
}
- (BOOL) hasAvatar {
  return resultAvatar.hasAvatar;
}
- (SSKProtoAttachmentPointer*) avatar {
  return resultAvatar.avatar;
}
- (SSKProtoDataMessageContactAvatarBuilder*) setAvatar:(SSKProtoAttachmentPointer*) value {
  resultAvatar.hasAvatar = YES;
  resultAvatar.avatar = value;
  return self;
}
- (SSKProtoDataMessageContactAvatarBuilder*) setAvatarBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue {
  return [self setAvatar:[builderForValue build]];
}
- (SSKProtoDataMessageContactAvatarBuilder*) mergeAvatar:(SSKProtoAttachmentPointer*) value {
  if (resultAvatar.hasAvatar &&
      resultAvatar.avatar != [SSKProtoAttachmentPointer defaultInstance]) {
    resultAvatar.avatar =
      [[[SSKProtoAttachmentPointer builderWithPrototype:resultAvatar.avatar] mergeFrom:value] buildPartial];
  } else {
    resultAvatar.avatar = value;
  }
  resultAvatar.hasAvatar = YES;
  return self;
}
- (SSKProtoDataMessageContactAvatarBuilder*) clearAvatar {
  resultAvatar.hasAvatar = NO;
  resultAvatar.avatar = [SSKProtoAttachmentPointer defaultInstance];
  return self;
}
- (BOOL) hasIsProfile {
  return resultAvatar.hasIsProfile;
}
- (BOOL) isProfile {
  return resultAvatar.isProfile;
}
- (SSKProtoDataMessageContactAvatarBuilder*) setIsProfile:(BOOL) value {
  resultAvatar.hasIsProfile = YES;
  resultAvatar.isProfile = value;
  return self;
}
- (SSKProtoDataMessageContactAvatarBuilder*) clearIsProfile {
  resultAvatar.hasIsProfile = NO;
  resultAvatar.isProfile = NO;
  return self;
}
@end

@interface SSKProtoDataMessageContactBuilder()
@property (strong) SSKProtoDataMessageContact* resultContact;
@end

@implementation SSKProtoDataMessageContactBuilder
@synthesize resultContact;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultContact = [[SSKProtoDataMessageContact alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultContact;
}
- (SSKProtoDataMessageContactBuilder*) clear {
  self.resultContact = [[SSKProtoDataMessageContact alloc] init];
  return self;
}
- (SSKProtoDataMessageContactBuilder*) clone {
  return [SSKProtoDataMessageContact builderWithPrototype:resultContact];
}
- (SSKProtoDataMessageContact*) defaultInstance {
  return [SSKProtoDataMessageContact defaultInstance];
}
- (SSKProtoDataMessageContact*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessageContact*) buildPartial {
  SSKProtoDataMessageContact* returnMe = resultContact;
  self.resultContact = nil;
  return returnMe;
}
- (SSKProtoDataMessageContactBuilder*) mergeFrom:(SSKProtoDataMessageContact*) other {
  if (other == [SSKProtoDataMessageContact defaultInstance]) {
    return self;
  }
  if (other.hasName) {
    [self mergeName:other.name];
  }
  if (other.numberArray.count > 0) {
    if (resultContact.numberArray == nil) {
      resultContact.numberArray = [[NSMutableArray alloc] initWithArray:other.numberArray];
    } else {
      [resultContact.numberArray addObjectsFromArray:other.numberArray];
    }
  }
  if (other.emailArray.count > 0) {
    if (resultContact.emailArray == nil) {
      resultContact.emailArray = [[NSMutableArray alloc] initWithArray:other.emailArray];
    } else {
      [resultContact.emailArray addObjectsFromArray:other.emailArray];
    }
  }
  if (other.addressArray.count > 0) {
    if (resultContact.addressArray == nil) {
      resultContact.addressArray = [[NSMutableArray alloc] initWithArray:other.addressArray];
    } else {
      [resultContact.addressArray addObjectsFromArray:other.addressArray];
    }
  }
  if (other.hasAvatar) {
    [self mergeAvatar:other.avatar];
  }
  if (other.hasOrganization) {
    [self setOrganization:other.organization];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageContactBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageContactBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoDataMessageContactNameBuilder* subBuilder = [SSKProtoDataMessageContactName builder];
        if (self.hasName) {
          [subBuilder mergeFrom:self.name];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setName:[subBuilder buildPartial]];
        break;
      }
      case 26: {
        SSKProtoDataMessageContactPhoneBuilder* subBuilder = [SSKProtoDataMessageContactPhone builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addNumber:[subBuilder buildPartial]];
        break;
      }
      case 34: {
        SSKProtoDataMessageContactEmailBuilder* subBuilder = [SSKProtoDataMessageContactEmail builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addEmail:[subBuilder buildPartial]];
        break;
      }
      case 42: {
        SSKProtoDataMessageContactPostalAddressBuilder* subBuilder = [SSKProtoDataMessageContactPostalAddress builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addAddress:[subBuilder buildPartial]];
        break;
      }
      case 50: {
        SSKProtoDataMessageContactAvatarBuilder* subBuilder = [SSKProtoDataMessageContactAvatar builder];
        if (self.hasAvatar) {
          [subBuilder mergeFrom:self.avatar];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAvatar:[subBuilder buildPartial]];
        break;
      }
      case 58: {
        [self setOrganization:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasName {
  return resultContact.hasName;
}
- (SSKProtoDataMessageContactName*) name {
  return resultContact.name;
}
- (SSKProtoDataMessageContactBuilder*) setName:(SSKProtoDataMessageContactName*) value {
  resultContact.hasName = YES;
  resultContact.name = value;
  return self;
}
- (SSKProtoDataMessageContactBuilder*) setNameBuilder:(SSKProtoDataMessageContactNameBuilder*) builderForValue {
  return [self setName:[builderForValue build]];
}
- (SSKProtoDataMessageContactBuilder*) mergeName:(SSKProtoDataMessageContactName*) value {
  if (resultContact.hasName &&
      resultContact.name != [SSKProtoDataMessageContactName defaultInstance]) {
    resultContact.name =
      [[[SSKProtoDataMessageContactName builderWithPrototype:resultContact.name] mergeFrom:value] buildPartial];
  } else {
    resultContact.name = value;
  }
  resultContact.hasName = YES;
  return self;
}
- (SSKProtoDataMessageContactBuilder*) clearName {
  resultContact.hasName = NO;
  resultContact.name = [SSKProtoDataMessageContactName defaultInstance];
  return self;
}
- (NSMutableArray<SSKProtoDataMessageContactPhone*> *)number {
  return resultContact.numberArray;
}
- (SSKProtoDataMessageContactPhone*)numberAtIndex:(NSUInteger)index {
  return [resultContact numberAtIndex:index];
}
- (SSKProtoDataMessageContactBuilder *)addNumber:(SSKProtoDataMessageContactPhone*)value {
  if (resultContact.numberArray == nil) {
    resultContact.numberArray = [[NSMutableArray alloc]init];
  }
  [resultContact.numberArray addObject:value];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)setNumberArray:(NSArray<SSKProtoDataMessageContactPhone*> *)array {
  resultContact.numberArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)clearNumber {
  resultContact.numberArray = nil;
  return self;
}
- (NSMutableArray<SSKProtoDataMessageContactEmail*> *)email {
  return resultContact.emailArray;
}
- (SSKProtoDataMessageContactEmail*)emailAtIndex:(NSUInteger)index {
  return [resultContact emailAtIndex:index];
}
- (SSKProtoDataMessageContactBuilder *)addEmail:(SSKProtoDataMessageContactEmail*)value {
  if (resultContact.emailArray == nil) {
    resultContact.emailArray = [[NSMutableArray alloc]init];
  }
  [resultContact.emailArray addObject:value];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)setEmailArray:(NSArray<SSKProtoDataMessageContactEmail*> *)array {
  resultContact.emailArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)clearEmail {
  resultContact.emailArray = nil;
  return self;
}
- (NSMutableArray<SSKProtoDataMessageContactPostalAddress*> *)address {
  return resultContact.addressArray;
}
- (SSKProtoDataMessageContactPostalAddress*)addressAtIndex:(NSUInteger)index {
  return [resultContact addressAtIndex:index];
}
- (SSKProtoDataMessageContactBuilder *)addAddress:(SSKProtoDataMessageContactPostalAddress*)value {
  if (resultContact.addressArray == nil) {
    resultContact.addressArray = [[NSMutableArray alloc]init];
  }
  [resultContact.addressArray addObject:value];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)setAddressArray:(NSArray<SSKProtoDataMessageContactPostalAddress*> *)array {
  resultContact.addressArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageContactBuilder *)clearAddress {
  resultContact.addressArray = nil;
  return self;
}
- (BOOL) hasAvatar {
  return resultContact.hasAvatar;
}
- (SSKProtoDataMessageContactAvatar*) avatar {
  return resultContact.avatar;
}
- (SSKProtoDataMessageContactBuilder*) setAvatar:(SSKProtoDataMessageContactAvatar*) value {
  resultContact.hasAvatar = YES;
  resultContact.avatar = value;
  return self;
}
- (SSKProtoDataMessageContactBuilder*) setAvatarBuilder:(SSKProtoDataMessageContactAvatarBuilder*) builderForValue {
  return [self setAvatar:[builderForValue build]];
}
- (SSKProtoDataMessageContactBuilder*) mergeAvatar:(SSKProtoDataMessageContactAvatar*) value {
  if (resultContact.hasAvatar &&
      resultContact.avatar != [SSKProtoDataMessageContactAvatar defaultInstance]) {
    resultContact.avatar =
      [[[SSKProtoDataMessageContactAvatar builderWithPrototype:resultContact.avatar] mergeFrom:value] buildPartial];
  } else {
    resultContact.avatar = value;
  }
  resultContact.hasAvatar = YES;
  return self;
}
- (SSKProtoDataMessageContactBuilder*) clearAvatar {
  resultContact.hasAvatar = NO;
  resultContact.avatar = [SSKProtoDataMessageContactAvatar defaultInstance];
  return self;
}
- (BOOL) hasOrganization {
  return resultContact.hasOrganization;
}
- (NSString*) organization {
  return resultContact.organization;
}
- (SSKProtoDataMessageContactBuilder*) setOrganization:(NSString*) value {
  resultContact.hasOrganization = YES;
  resultContact.organization = value;
  return self;
}
- (SSKProtoDataMessageContactBuilder*) clearOrganization {
  resultContact.hasOrganization = NO;
  resultContact.organization = @"";
  return self;
}
@end

@interface SSKProtoDataMessageBuilder()
@property (strong) SSKProtoDataMessage* resultDataMessage;
@end

@implementation SSKProtoDataMessageBuilder
@synthesize resultDataMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultDataMessage = [[SSKProtoDataMessage alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultDataMessage;
}
- (SSKProtoDataMessageBuilder*) clear {
  self.resultDataMessage = [[SSKProtoDataMessage alloc] init];
  return self;
}
- (SSKProtoDataMessageBuilder*) clone {
  return [SSKProtoDataMessage builderWithPrototype:resultDataMessage];
}
- (SSKProtoDataMessage*) defaultInstance {
  return [SSKProtoDataMessage defaultInstance];
}
- (SSKProtoDataMessage*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoDataMessage*) buildPartial {
  SSKProtoDataMessage* returnMe = resultDataMessage;
  self.resultDataMessage = nil;
  return returnMe;
}
- (SSKProtoDataMessageBuilder*) mergeFrom:(SSKProtoDataMessage*) other {
  if (other == [SSKProtoDataMessage defaultInstance]) {
    return self;
  }
  if (other.hasBody) {
    [self setBody:other.body];
  }
  if (other.attachmentsArray.count > 0) {
    if (resultDataMessage.attachmentsArray == nil) {
      resultDataMessage.attachmentsArray = [[NSMutableArray alloc] initWithArray:other.attachmentsArray];
    } else {
      [resultDataMessage.attachmentsArray addObjectsFromArray:other.attachmentsArray];
    }
  }
  if (other.hasGroup) {
    [self mergeGroup:other.group];
  }
  if (other.hasFlags) {
    [self setFlags:other.flags];
  }
  if (other.hasExpireTimer) {
    [self setExpireTimer:other.expireTimer];
  }
  if (other.hasProfileKey) {
    [self setProfileKey:other.profileKey];
  }
  if (other.hasTimestamp) {
    [self setTimestamp:other.timestamp];
  }
  if (other.hasQuote) {
    [self mergeQuote:other.quote];
  }
  if (other.contactArray.count > 0) {
    if (resultDataMessage.contactArray == nil) {
      resultDataMessage.contactArray = [[NSMutableArray alloc] initWithArray:other.contactArray];
    } else {
      [resultDataMessage.contactArray addObjectsFromArray:other.contactArray];
    }
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoDataMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoDataMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setBody:[input readString]];
        break;
      }
      case 18: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addAttachments:[subBuilder buildPartial]];
        break;
      }
      case 26: {
        SSKProtoGroupContextBuilder* subBuilder = [SSKProtoGroupContext builder];
        if (self.hasGroup) {
          [subBuilder mergeFrom:self.group];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setGroup:[subBuilder buildPartial]];
        break;
      }
      case 32: {
        [self setFlags:[input readUInt32]];
        break;
      }
      case 40: {
        [self setExpireTimer:[input readUInt32]];
        break;
      }
      case 50: {
        [self setProfileKey:[input readData]];
        break;
      }
      case 56: {
        [self setTimestamp:[input readUInt64]];
        break;
      }
      case 66: {
        SSKProtoDataMessageQuoteBuilder* subBuilder = [SSKProtoDataMessageQuote builder];
        if (self.hasQuote) {
          [subBuilder mergeFrom:self.quote];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setQuote:[subBuilder buildPartial]];
        break;
      }
      case 74: {
        SSKProtoDataMessageContactBuilder* subBuilder = [SSKProtoDataMessageContact builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addContact:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasBody {
  return resultDataMessage.hasBody;
}
- (NSString*) body {
  return resultDataMessage.body;
}
- (SSKProtoDataMessageBuilder*) setBody:(NSString*) value {
  resultDataMessage.hasBody = YES;
  resultDataMessage.body = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearBody {
  resultDataMessage.hasBody = NO;
  resultDataMessage.body = @"";
  return self;
}
- (NSMutableArray<SSKProtoAttachmentPointer*> *)attachments {
  return resultDataMessage.attachmentsArray;
}
- (SSKProtoAttachmentPointer*)attachmentsAtIndex:(NSUInteger)index {
  return [resultDataMessage attachmentsAtIndex:index];
}
- (SSKProtoDataMessageBuilder *)addAttachments:(SSKProtoAttachmentPointer*)value {
  if (resultDataMessage.attachmentsArray == nil) {
    resultDataMessage.attachmentsArray = [[NSMutableArray alloc]init];
  }
  [resultDataMessage.attachmentsArray addObject:value];
  return self;
}
- (SSKProtoDataMessageBuilder *)setAttachmentsArray:(NSArray<SSKProtoAttachmentPointer*> *)array {
  resultDataMessage.attachmentsArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageBuilder *)clearAttachments {
  resultDataMessage.attachmentsArray = nil;
  return self;
}
- (BOOL) hasGroup {
  return resultDataMessage.hasGroup;
}
- (SSKProtoGroupContext*) group {
  return resultDataMessage.group;
}
- (SSKProtoDataMessageBuilder*) setGroup:(SSKProtoGroupContext*) value {
  resultDataMessage.hasGroup = YES;
  resultDataMessage.group = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) setGroupBuilder:(SSKProtoGroupContextBuilder*) builderForValue {
  return [self setGroup:[builderForValue build]];
}
- (SSKProtoDataMessageBuilder*) mergeGroup:(SSKProtoGroupContext*) value {
  if (resultDataMessage.hasGroup &&
      resultDataMessage.group != [SSKProtoGroupContext defaultInstance]) {
    resultDataMessage.group =
      [[[SSKProtoGroupContext builderWithPrototype:resultDataMessage.group] mergeFrom:value] buildPartial];
  } else {
    resultDataMessage.group = value;
  }
  resultDataMessage.hasGroup = YES;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearGroup {
  resultDataMessage.hasGroup = NO;
  resultDataMessage.group = [SSKProtoGroupContext defaultInstance];
  return self;
}
- (BOOL) hasFlags {
  return resultDataMessage.hasFlags;
}
- (UInt32) flags {
  return resultDataMessage.flags;
}
- (SSKProtoDataMessageBuilder*) setFlags:(UInt32) value {
  resultDataMessage.hasFlags = YES;
  resultDataMessage.flags = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearFlags {
  resultDataMessage.hasFlags = NO;
  resultDataMessage.flags = 0;
  return self;
}
- (BOOL) hasExpireTimer {
  return resultDataMessage.hasExpireTimer;
}
- (UInt32) expireTimer {
  return resultDataMessage.expireTimer;
}
- (SSKProtoDataMessageBuilder*) setExpireTimer:(UInt32) value {
  resultDataMessage.hasExpireTimer = YES;
  resultDataMessage.expireTimer = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearExpireTimer {
  resultDataMessage.hasExpireTimer = NO;
  resultDataMessage.expireTimer = 0;
  return self;
}
- (BOOL) hasProfileKey {
  return resultDataMessage.hasProfileKey;
}
- (NSData*) profileKey {
  return resultDataMessage.profileKey;
}
- (SSKProtoDataMessageBuilder*) setProfileKey:(NSData*) value {
  resultDataMessage.hasProfileKey = YES;
  resultDataMessage.profileKey = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearProfileKey {
  resultDataMessage.hasProfileKey = NO;
  resultDataMessage.profileKey = [NSData data];
  return self;
}
- (BOOL) hasTimestamp {
  return resultDataMessage.hasTimestamp;
}
- (UInt64) timestamp {
  return resultDataMessage.timestamp;
}
- (SSKProtoDataMessageBuilder*) setTimestamp:(UInt64) value {
  resultDataMessage.hasTimestamp = YES;
  resultDataMessage.timestamp = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearTimestamp {
  resultDataMessage.hasTimestamp = NO;
  resultDataMessage.timestamp = 0L;
  return self;
}
- (BOOL) hasQuote {
  return resultDataMessage.hasQuote;
}
- (SSKProtoDataMessageQuote*) quote {
  return resultDataMessage.quote;
}
- (SSKProtoDataMessageBuilder*) setQuote:(SSKProtoDataMessageQuote*) value {
  resultDataMessage.hasQuote = YES;
  resultDataMessage.quote = value;
  return self;
}
- (SSKProtoDataMessageBuilder*) setQuoteBuilder:(SSKProtoDataMessageQuoteBuilder*) builderForValue {
  return [self setQuote:[builderForValue build]];
}
- (SSKProtoDataMessageBuilder*) mergeQuote:(SSKProtoDataMessageQuote*) value {
  if (resultDataMessage.hasQuote &&
      resultDataMessage.quote != [SSKProtoDataMessageQuote defaultInstance]) {
    resultDataMessage.quote =
      [[[SSKProtoDataMessageQuote builderWithPrototype:resultDataMessage.quote] mergeFrom:value] buildPartial];
  } else {
    resultDataMessage.quote = value;
  }
  resultDataMessage.hasQuote = YES;
  return self;
}
- (SSKProtoDataMessageBuilder*) clearQuote {
  resultDataMessage.hasQuote = NO;
  resultDataMessage.quote = [SSKProtoDataMessageQuote defaultInstance];
  return self;
}
- (NSMutableArray<SSKProtoDataMessageContact*> *)contact {
  return resultDataMessage.contactArray;
}
- (SSKProtoDataMessageContact*)contactAtIndex:(NSUInteger)index {
  return [resultDataMessage contactAtIndex:index];
}
- (SSKProtoDataMessageBuilder *)addContact:(SSKProtoDataMessageContact*)value {
  if (resultDataMessage.contactArray == nil) {
    resultDataMessage.contactArray = [[NSMutableArray alloc]init];
  }
  [resultDataMessage.contactArray addObject:value];
  return self;
}
- (SSKProtoDataMessageBuilder *)setContactArray:(NSArray<SSKProtoDataMessageContact*> *)array {
  resultDataMessage.contactArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoDataMessageBuilder *)clearContact {
  resultDataMessage.contactArray = nil;
  return self;
}
@end

@interface SSKProtoNullMessage ()
@property (strong) NSData* padding;
@end

@implementation SSKProtoNullMessage

- (BOOL) hasPadding {
  return !!hasPadding_;
}
- (void) setHasPadding:(BOOL) _value_ {
  hasPadding_ = !!_value_;
}
@synthesize padding;
- (instancetype) init {
  if ((self = [super init])) {
    self.padding = [NSData data];
  }
  return self;
}
static SSKProtoNullMessage* defaultSSKProtoNullMessageInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoNullMessage class]) {
    defaultSSKProtoNullMessageInstance = [[SSKProtoNullMessage alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoNullMessageInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoNullMessageInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasPadding) {
    [output writeData:1 value:self.padding];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasPadding) {
    size_ += computeDataSize(1, self.padding);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoNullMessage*) parseFromData:(NSData*) data {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromData:data] build];
}
+ (SSKProtoNullMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoNullMessage*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromInputStream:input] build];
}
+ (SSKProtoNullMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoNullMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoNullMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoNullMessage*)[[[SSKProtoNullMessage builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoNullMessageBuilder*) builder {
  return [[SSKProtoNullMessageBuilder alloc] init];
}
+ (SSKProtoNullMessageBuilder*) builderWithPrototype:(SSKProtoNullMessage*) prototype {
  return [[SSKProtoNullMessage builder] mergeFrom:prototype];
}
- (SSKProtoNullMessageBuilder*) builder {
  return [SSKProtoNullMessage builder];
}
- (SSKProtoNullMessageBuilder*) toBuilder {
  return [SSKProtoNullMessage builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasPadding) {
    [output appendFormat:@"%@%@: %@\n", indent, @"padding", self.padding];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasPadding) {
    [dictionary setObject: self.padding forKey: @"padding"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoNullMessage class]]) {
    return NO;
  }
  SSKProtoNullMessage *otherMessage = other;
  return
      self.hasPadding == otherMessage.hasPadding &&
      (!self.hasPadding || [self.padding isEqual:otherMessage.padding]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasPadding) {
    hashCode = hashCode * 31 + [self.padding hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoNullMessageBuilder()
@property (strong) SSKProtoNullMessage* resultNullMessage;
@end

@implementation SSKProtoNullMessageBuilder
@synthesize resultNullMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultNullMessage = [[SSKProtoNullMessage alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultNullMessage;
}
- (SSKProtoNullMessageBuilder*) clear {
  self.resultNullMessage = [[SSKProtoNullMessage alloc] init];
  return self;
}
- (SSKProtoNullMessageBuilder*) clone {
  return [SSKProtoNullMessage builderWithPrototype:resultNullMessage];
}
- (SSKProtoNullMessage*) defaultInstance {
  return [SSKProtoNullMessage defaultInstance];
}
- (SSKProtoNullMessage*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoNullMessage*) buildPartial {
  SSKProtoNullMessage* returnMe = resultNullMessage;
  self.resultNullMessage = nil;
  return returnMe;
}
- (SSKProtoNullMessageBuilder*) mergeFrom:(SSKProtoNullMessage*) other {
  if (other == [SSKProtoNullMessage defaultInstance]) {
    return self;
  }
  if (other.hasPadding) {
    [self setPadding:other.padding];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoNullMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoNullMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setPadding:[input readData]];
        break;
      }
    }
  }
}
- (BOOL) hasPadding {
  return resultNullMessage.hasPadding;
}
- (NSData*) padding {
  return resultNullMessage.padding;
}
- (SSKProtoNullMessageBuilder*) setPadding:(NSData*) value {
  resultNullMessage.hasPadding = YES;
  resultNullMessage.padding = value;
  return self;
}
- (SSKProtoNullMessageBuilder*) clearPadding {
  resultNullMessage.hasPadding = NO;
  resultNullMessage.padding = [NSData data];
  return self;
}
@end

@interface SSKProtoReceiptMessage ()
@property SSKProtoReceiptMessageType type;
@property (strong) PBAppendableArray * timestampArray;
@end

@implementation SSKProtoReceiptMessage

- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
@synthesize timestampArray;
@dynamic timestamp;
- (instancetype) init {
  if ((self = [super init])) {
    self.type = SSKProtoReceiptMessageTypeDelivery;
  }
  return self;
}
static SSKProtoReceiptMessage* defaultSSKProtoReceiptMessageInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoReceiptMessage class]) {
    defaultSSKProtoReceiptMessageInstance = [[SSKProtoReceiptMessage alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoReceiptMessageInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoReceiptMessageInstance;
}
- (PBArray *)timestamp {
  return timestampArray;
}
- (UInt64)timestampAtIndex:(NSUInteger)index {
  return [timestampArray uint64AtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasType) {
    [output writeEnum:1 value:self.type];
  }
  const NSUInteger timestampArrayCount = self.timestampArray.count;
  if (timestampArrayCount > 0) {
    const UInt64 *values = (const UInt64 *)self.timestampArray.data;
    for (NSUInteger i = 0; i < timestampArrayCount; ++i) {
      [output writeUInt64:2 value:values[i]];
    }
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasType) {
    size_ += computeEnumSize(1, self.type);
  }
  {
    __block SInt32 dataSize = 0;
    const NSUInteger count = self.timestampArray.count;
    const UInt64 *values = (const UInt64 *)self.timestampArray.data;
    for (NSUInteger i = 0; i < count; ++i) {
      dataSize += computeUInt64SizeNoTag(values[i]);
    }
    size_ += dataSize;
    size_ += (SInt32)(1 * count);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoReceiptMessage*) parseFromData:(NSData*) data {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromData:data] build];
}
+ (SSKProtoReceiptMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoReceiptMessage*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromInputStream:input] build];
}
+ (SSKProtoReceiptMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoReceiptMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoReceiptMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoReceiptMessage*)[[[SSKProtoReceiptMessage builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoReceiptMessageBuilder*) builder {
  return [[SSKProtoReceiptMessageBuilder alloc] init];
}
+ (SSKProtoReceiptMessageBuilder*) builderWithPrototype:(SSKProtoReceiptMessage*) prototype {
  return [[SSKProtoReceiptMessage builder] mergeFrom:prototype];
}
- (SSKProtoReceiptMessageBuilder*) builder {
  return [SSKProtoReceiptMessage builder];
}
- (SSKProtoReceiptMessageBuilder*) toBuilder {
  return [SSKProtoReceiptMessage builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoReceiptMessageType(self.type)];
  }
  [self.timestampArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@: %@\n", indent, @"timestamp", obj];
  }];
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  NSMutableArray * timestampArrayArray = [NSMutableArray new];
  NSUInteger timestampArrayCount=self.timestampArray.count;
  for(int i=0;i<timestampArrayCount;i++){
    [timestampArrayArray addObject: @([self.timestampArray uint64AtIndex:i])];
  }
  [dictionary setObject: timestampArrayArray forKey: @"timestamp"];
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoReceiptMessage class]]) {
    return NO;
  }
  SSKProtoReceiptMessage *otherMessage = other;
  return
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      [self.timestampArray isEqualToArray:otherMessage.timestampArray] &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  [self.timestampArray enumerateObjectsUsingBlock:^(NSNumber *obj, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [obj longValue];
  }];
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoReceiptMessageTypeIsValidValue(SSKProtoReceiptMessageType value) {
  switch (value) {
    case SSKProtoReceiptMessageTypeDelivery:
    case SSKProtoReceiptMessageTypeRead:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoReceiptMessageType(SSKProtoReceiptMessageType value) {
  switch (value) {
    case SSKProtoReceiptMessageTypeDelivery:
      return @"SSKProtoReceiptMessageTypeDelivery";
    case SSKProtoReceiptMessageTypeRead:
      return @"SSKProtoReceiptMessageTypeRead";
    default:
      return nil;
  }
}

@interface SSKProtoReceiptMessageBuilder()
@property (strong) SSKProtoReceiptMessage* resultReceiptMessage;
@end

@implementation SSKProtoReceiptMessageBuilder
@synthesize resultReceiptMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultReceiptMessage = [[SSKProtoReceiptMessage alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultReceiptMessage;
}
- (SSKProtoReceiptMessageBuilder*) clear {
  self.resultReceiptMessage = [[SSKProtoReceiptMessage alloc] init];
  return self;
}
- (SSKProtoReceiptMessageBuilder*) clone {
  return [SSKProtoReceiptMessage builderWithPrototype:resultReceiptMessage];
}
- (SSKProtoReceiptMessage*) defaultInstance {
  return [SSKProtoReceiptMessage defaultInstance];
}
- (SSKProtoReceiptMessage*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoReceiptMessage*) buildPartial {
  SSKProtoReceiptMessage* returnMe = resultReceiptMessage;
  self.resultReceiptMessage = nil;
  return returnMe;
}
- (SSKProtoReceiptMessageBuilder*) mergeFrom:(SSKProtoReceiptMessage*) other {
  if (other == [SSKProtoReceiptMessage defaultInstance]) {
    return self;
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.timestampArray.count > 0) {
    if (resultReceiptMessage.timestampArray == nil) {
      resultReceiptMessage.timestampArray = [other.timestampArray copy];
    } else {
      [resultReceiptMessage.timestampArray appendArray:other.timestampArray];
    }
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoReceiptMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoReceiptMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        SSKProtoReceiptMessageType value = (SSKProtoReceiptMessageType)[input readEnum];
        if (SSKProtoReceiptMessageTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:1 value:value];
        }
        break;
      }
      case 16: {
        [self addTimestamp:[input readUInt64]];
        break;
      }
    }
  }
}
- (BOOL) hasType {
  return resultReceiptMessage.hasType;
}
- (SSKProtoReceiptMessageType) type {
  return resultReceiptMessage.type;
}
- (SSKProtoReceiptMessageBuilder*) setType:(SSKProtoReceiptMessageType) value {
  resultReceiptMessage.hasType = YES;
  resultReceiptMessage.type = value;
  return self;
}
- (SSKProtoReceiptMessageBuilder*) clearType {
  resultReceiptMessage.hasType = NO;
  resultReceiptMessage.type = SSKProtoReceiptMessageTypeDelivery;
  return self;
}
- (PBAppendableArray *)timestamp {
  return resultReceiptMessage.timestampArray;
}
- (UInt64)timestampAtIndex:(NSUInteger)index {
  return [resultReceiptMessage timestampAtIndex:index];
}
- (SSKProtoReceiptMessageBuilder *)addTimestamp:(UInt64)value {
  if (resultReceiptMessage.timestampArray == nil) {
    resultReceiptMessage.timestampArray = [PBAppendableArray arrayWithValueType:PBArrayValueTypeUInt64];
  }
  [resultReceiptMessage.timestampArray addUint64:value];
  return self;
}
- (SSKProtoReceiptMessageBuilder *)setTimestampArray:(NSArray *)array {
  resultReceiptMessage.timestampArray = [PBAppendableArray arrayWithArray:array valueType:PBArrayValueTypeUInt64];
  return self;
}
- (SSKProtoReceiptMessageBuilder *)setTimestampValues:(const UInt64 *)values count:(NSUInteger)count {
  resultReceiptMessage.timestampArray = [PBAppendableArray arrayWithValues:values count:count valueType:PBArrayValueTypeUInt64];
  return self;
}
- (SSKProtoReceiptMessageBuilder *)clearTimestamp {
  resultReceiptMessage.timestampArray = nil;
  return self;
}
@end

@interface SSKProtoVerified ()
@property (strong) NSString* destination;
@property (strong) NSData* identityKey;
@property SSKProtoVerifiedState state;
@property (strong) NSData* nullMessage;
@end

@implementation SSKProtoVerified

- (BOOL) hasDestination {
  return !!hasDestination_;
}
- (void) setHasDestination:(BOOL) _value_ {
  hasDestination_ = !!_value_;
}
@synthesize destination;
- (BOOL) hasIdentityKey {
  return !!hasIdentityKey_;
}
- (void) setHasIdentityKey:(BOOL) _value_ {
  hasIdentityKey_ = !!_value_;
}
@synthesize identityKey;
- (BOOL) hasState {
  return !!hasState_;
}
- (void) setHasState:(BOOL) _value_ {
  hasState_ = !!_value_;
}
@synthesize state;
- (BOOL) hasNullMessage {
  return !!hasNullMessage_;
}
- (void) setHasNullMessage:(BOOL) _value_ {
  hasNullMessage_ = !!_value_;
}
@synthesize nullMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.destination = @"";
    self.identityKey = [NSData data];
    self.state = SSKProtoVerifiedStateDefault;
    self.nullMessage = [NSData data];
  }
  return self;
}
static SSKProtoVerified* defaultSSKProtoVerifiedInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoVerified class]) {
    defaultSSKProtoVerifiedInstance = [[SSKProtoVerified alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoVerifiedInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoVerifiedInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasDestination) {
    [output writeString:1 value:self.destination];
  }
  if (self.hasIdentityKey) {
    [output writeData:2 value:self.identityKey];
  }
  if (self.hasState) {
    [output writeEnum:3 value:self.state];
  }
  if (self.hasNullMessage) {
    [output writeData:4 value:self.nullMessage];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasDestination) {
    size_ += computeStringSize(1, self.destination);
  }
  if (self.hasIdentityKey) {
    size_ += computeDataSize(2, self.identityKey);
  }
  if (self.hasState) {
    size_ += computeEnumSize(3, self.state);
  }
  if (self.hasNullMessage) {
    size_ += computeDataSize(4, self.nullMessage);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoVerified*) parseFromData:(NSData*) data {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromData:data] build];
}
+ (SSKProtoVerified*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoVerified*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromInputStream:input] build];
}
+ (SSKProtoVerified*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoVerified*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoVerified*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoVerified*)[[[SSKProtoVerified builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoVerifiedBuilder*) builder {
  return [[SSKProtoVerifiedBuilder alloc] init];
}
+ (SSKProtoVerifiedBuilder*) builderWithPrototype:(SSKProtoVerified*) prototype {
  return [[SSKProtoVerified builder] mergeFrom:prototype];
}
- (SSKProtoVerifiedBuilder*) builder {
  return [SSKProtoVerified builder];
}
- (SSKProtoVerifiedBuilder*) toBuilder {
  return [SSKProtoVerified builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasDestination) {
    [output appendFormat:@"%@%@: %@\n", indent, @"destination", self.destination];
  }
  if (self.hasIdentityKey) {
    [output appendFormat:@"%@%@: %@\n", indent, @"identityKey", self.identityKey];
  }
  if (self.hasState) {
    [output appendFormat:@"%@%@: %@\n", indent, @"state", NSStringFromSSKProtoVerifiedState(self.state)];
  }
  if (self.hasNullMessage) {
    [output appendFormat:@"%@%@: %@\n", indent, @"nullMessage", self.nullMessage];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasDestination) {
    [dictionary setObject: self.destination forKey: @"destination"];
  }
  if (self.hasIdentityKey) {
    [dictionary setObject: self.identityKey forKey: @"identityKey"];
  }
  if (self.hasState) {
    [dictionary setObject: @(self.state) forKey: @"state"];
  }
  if (self.hasNullMessage) {
    [dictionary setObject: self.nullMessage forKey: @"nullMessage"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoVerified class]]) {
    return NO;
  }
  SSKProtoVerified *otherMessage = other;
  return
      self.hasDestination == otherMessage.hasDestination &&
      (!self.hasDestination || [self.destination isEqual:otherMessage.destination]) &&
      self.hasIdentityKey == otherMessage.hasIdentityKey &&
      (!self.hasIdentityKey || [self.identityKey isEqual:otherMessage.identityKey]) &&
      self.hasState == otherMessage.hasState &&
      (!self.hasState || self.state == otherMessage.state) &&
      self.hasNullMessage == otherMessage.hasNullMessage &&
      (!self.hasNullMessage || [self.nullMessage isEqual:otherMessage.nullMessage]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasDestination) {
    hashCode = hashCode * 31 + [self.destination hash];
  }
  if (self.hasIdentityKey) {
    hashCode = hashCode * 31 + [self.identityKey hash];
  }
  if (self.hasState) {
    hashCode = hashCode * 31 + self.state;
  }
  if (self.hasNullMessage) {
    hashCode = hashCode * 31 + [self.nullMessage hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoVerifiedStateIsValidValue(SSKProtoVerifiedState value) {
  switch (value) {
    case SSKProtoVerifiedStateDefault:
    case SSKProtoVerifiedStateVerified:
    case SSKProtoVerifiedStateUnverified:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoVerifiedState(SSKProtoVerifiedState value) {
  switch (value) {
    case SSKProtoVerifiedStateDefault:
      return @"SSKProtoVerifiedStateDefault";
    case SSKProtoVerifiedStateVerified:
      return @"SSKProtoVerifiedStateVerified";
    case SSKProtoVerifiedStateUnverified:
      return @"SSKProtoVerifiedStateUnverified";
    default:
      return nil;
  }
}

@interface SSKProtoVerifiedBuilder()
@property (strong) SSKProtoVerified* resultVerified;
@end

@implementation SSKProtoVerifiedBuilder
@synthesize resultVerified;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultVerified = [[SSKProtoVerified alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultVerified;
}
- (SSKProtoVerifiedBuilder*) clear {
  self.resultVerified = [[SSKProtoVerified alloc] init];
  return self;
}
- (SSKProtoVerifiedBuilder*) clone {
  return [SSKProtoVerified builderWithPrototype:resultVerified];
}
- (SSKProtoVerified*) defaultInstance {
  return [SSKProtoVerified defaultInstance];
}
- (SSKProtoVerified*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoVerified*) buildPartial {
  SSKProtoVerified* returnMe = resultVerified;
  self.resultVerified = nil;
  return returnMe;
}
- (SSKProtoVerifiedBuilder*) mergeFrom:(SSKProtoVerified*) other {
  if (other == [SSKProtoVerified defaultInstance]) {
    return self;
  }
  if (other.hasDestination) {
    [self setDestination:other.destination];
  }
  if (other.hasIdentityKey) {
    [self setIdentityKey:other.identityKey];
  }
  if (other.hasState) {
    [self setState:other.state];
  }
  if (other.hasNullMessage) {
    [self setNullMessage:other.nullMessage];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoVerifiedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoVerifiedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setDestination:[input readString]];
        break;
      }
      case 18: {
        [self setIdentityKey:[input readData]];
        break;
      }
      case 24: {
        SSKProtoVerifiedState value = (SSKProtoVerifiedState)[input readEnum];
        if (SSKProtoVerifiedStateIsValidValue(value)) {
          [self setState:value];
        } else {
          [unknownFields mergeVarintField:3 value:value];
        }
        break;
      }
      case 34: {
        [self setNullMessage:[input readData]];
        break;
      }
    }
  }
}
- (BOOL) hasDestination {
  return resultVerified.hasDestination;
}
- (NSString*) destination {
  return resultVerified.destination;
}
- (SSKProtoVerifiedBuilder*) setDestination:(NSString*) value {
  resultVerified.hasDestination = YES;
  resultVerified.destination = value;
  return self;
}
- (SSKProtoVerifiedBuilder*) clearDestination {
  resultVerified.hasDestination = NO;
  resultVerified.destination = @"";
  return self;
}
- (BOOL) hasIdentityKey {
  return resultVerified.hasIdentityKey;
}
- (NSData*) identityKey {
  return resultVerified.identityKey;
}
- (SSKProtoVerifiedBuilder*) setIdentityKey:(NSData*) value {
  resultVerified.hasIdentityKey = YES;
  resultVerified.identityKey = value;
  return self;
}
- (SSKProtoVerifiedBuilder*) clearIdentityKey {
  resultVerified.hasIdentityKey = NO;
  resultVerified.identityKey = [NSData data];
  return self;
}
- (BOOL) hasState {
  return resultVerified.hasState;
}
- (SSKProtoVerifiedState) state {
  return resultVerified.state;
}
- (SSKProtoVerifiedBuilder*) setState:(SSKProtoVerifiedState) value {
  resultVerified.hasState = YES;
  resultVerified.state = value;
  return self;
}
- (SSKProtoVerifiedBuilder*) clearState {
  resultVerified.hasState = NO;
  resultVerified.state = SSKProtoVerifiedStateDefault;
  return self;
}
- (BOOL) hasNullMessage {
  return resultVerified.hasNullMessage;
}
- (NSData*) nullMessage {
  return resultVerified.nullMessage;
}
- (SSKProtoVerifiedBuilder*) setNullMessage:(NSData*) value {
  resultVerified.hasNullMessage = YES;
  resultVerified.nullMessage = value;
  return self;
}
- (SSKProtoVerifiedBuilder*) clearNullMessage {
  resultVerified.hasNullMessage = NO;
  resultVerified.nullMessage = [NSData data];
  return self;
}
@end

@interface SSKProtoSyncMessage ()
@property (strong) SSKProtoSyncMessageSent* sent;
@property (strong) SSKProtoSyncMessageContacts* contacts;
@property (strong) SSKProtoSyncMessageGroups* groups;
@property (strong) SSKProtoSyncMessageRequest* request;
@property (strong) NSMutableArray<SSKProtoSyncMessageRead*> * readArray;
@property (strong) SSKProtoSyncMessageBlocked* blocked;
@property (strong) SSKProtoVerified* verified;
@property (strong) SSKProtoSyncMessageConfiguration* configuration;
@property (strong) NSData* padding;
@end

@implementation SSKProtoSyncMessage

- (BOOL) hasSent {
  return !!hasSent_;
}
- (void) setHasSent:(BOOL) _value_ {
  hasSent_ = !!_value_;
}
@synthesize sent;
- (BOOL) hasContacts {
  return !!hasContacts_;
}
- (void) setHasContacts:(BOOL) _value_ {
  hasContacts_ = !!_value_;
}
@synthesize contacts;
- (BOOL) hasGroups {
  return !!hasGroups_;
}
- (void) setHasGroups:(BOOL) _value_ {
  hasGroups_ = !!_value_;
}
@synthesize groups;
- (BOOL) hasRequest {
  return !!hasRequest_;
}
- (void) setHasRequest:(BOOL) _value_ {
  hasRequest_ = !!_value_;
}
@synthesize request;
@synthesize readArray;
@dynamic read;
- (BOOL) hasBlocked {
  return !!hasBlocked_;
}
- (void) setHasBlocked:(BOOL) _value_ {
  hasBlocked_ = !!_value_;
}
@synthesize blocked;
- (BOOL) hasVerified {
  return !!hasVerified_;
}
- (void) setHasVerified:(BOOL) _value_ {
  hasVerified_ = !!_value_;
}
@synthesize verified;
- (BOOL) hasConfiguration {
  return !!hasConfiguration_;
}
- (void) setHasConfiguration:(BOOL) _value_ {
  hasConfiguration_ = !!_value_;
}
@synthesize configuration;
- (BOOL) hasPadding {
  return !!hasPadding_;
}
- (void) setHasPadding:(BOOL) _value_ {
  hasPadding_ = !!_value_;
}
@synthesize padding;
- (instancetype) init {
  if ((self = [super init])) {
    self.sent = [SSKProtoSyncMessageSent defaultInstance];
    self.contacts = [SSKProtoSyncMessageContacts defaultInstance];
    self.groups = [SSKProtoSyncMessageGroups defaultInstance];
    self.request = [SSKProtoSyncMessageRequest defaultInstance];
    self.blocked = [SSKProtoSyncMessageBlocked defaultInstance];
    self.verified = [SSKProtoVerified defaultInstance];
    self.configuration = [SSKProtoSyncMessageConfiguration defaultInstance];
    self.padding = [NSData data];
  }
  return self;
}
static SSKProtoSyncMessage* defaultSSKProtoSyncMessageInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessage class]) {
    defaultSSKProtoSyncMessageInstance = [[SSKProtoSyncMessage alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageInstance;
}
- (NSArray<SSKProtoSyncMessageRead*> *)read {
  return readArray;
}
- (SSKProtoSyncMessageRead*)readAtIndex:(NSUInteger)index {
  return [readArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasSent) {
    [output writeMessage:1 value:self.sent];
  }
  if (self.hasContacts) {
    [output writeMessage:2 value:self.contacts];
  }
  if (self.hasGroups) {
    [output writeMessage:3 value:self.groups];
  }
  if (self.hasRequest) {
    [output writeMessage:4 value:self.request];
  }
  [self.readArray enumerateObjectsUsingBlock:^(SSKProtoSyncMessageRead *element, NSUInteger idx, BOOL *stop) {
    [output writeMessage:5 value:element];
  }];
  if (self.hasBlocked) {
    [output writeMessage:6 value:self.blocked];
  }
  if (self.hasVerified) {
    [output writeMessage:7 value:self.verified];
  }
  if (self.hasPadding) {
    [output writeData:8 value:self.padding];
  }
  if (self.hasConfiguration) {
    [output writeMessage:9 value:self.configuration];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasSent) {
    size_ += computeMessageSize(1, self.sent);
  }
  if (self.hasContacts) {
    size_ += computeMessageSize(2, self.contacts);
  }
  if (self.hasGroups) {
    size_ += computeMessageSize(3, self.groups);
  }
  if (self.hasRequest) {
    size_ += computeMessageSize(4, self.request);
  }
  [self.readArray enumerateObjectsUsingBlock:^(SSKProtoSyncMessageRead *element, NSUInteger idx, BOOL *stop) {
    size_ += computeMessageSize(5, element);
  }];
  if (self.hasBlocked) {
    size_ += computeMessageSize(6, self.blocked);
  }
  if (self.hasVerified) {
    size_ += computeMessageSize(7, self.verified);
  }
  if (self.hasPadding) {
    size_ += computeDataSize(8, self.padding);
  }
  if (self.hasConfiguration) {
    size_ += computeMessageSize(9, self.configuration);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessage*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessage*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessage*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessage*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessage*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessage*)[[[SSKProtoSyncMessage builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageBuilder*) builder {
  return [[SSKProtoSyncMessageBuilder alloc] init];
}
+ (SSKProtoSyncMessageBuilder*) builderWithPrototype:(SSKProtoSyncMessage*) prototype {
  return [[SSKProtoSyncMessage builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageBuilder*) builder {
  return [SSKProtoSyncMessage builder];
}
- (SSKProtoSyncMessageBuilder*) toBuilder {
  return [SSKProtoSyncMessage builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasSent) {
    [output appendFormat:@"%@%@ {\n", indent, @"sent"];
    [self.sent writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasContacts) {
    [output appendFormat:@"%@%@ {\n", indent, @"contacts"];
    [self.contacts writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasGroups) {
    [output appendFormat:@"%@%@ {\n", indent, @"groups"];
    [self.groups writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasRequest) {
    [output appendFormat:@"%@%@ {\n", indent, @"request"];
    [self.request writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.readArray enumerateObjectsUsingBlock:^(SSKProtoSyncMessageRead *element, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@ {\n", indent, @"read"];
    [element writeDescriptionTo:output
                     withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }];
  if (self.hasBlocked) {
    [output appendFormat:@"%@%@ {\n", indent, @"blocked"];
    [self.blocked writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasVerified) {
    [output appendFormat:@"%@%@ {\n", indent, @"verified"];
    [self.verified writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasPadding) {
    [output appendFormat:@"%@%@: %@\n", indent, @"padding", self.padding];
  }
  if (self.hasConfiguration) {
    [output appendFormat:@"%@%@ {\n", indent, @"configuration"];
    [self.configuration writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasSent) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.sent storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"sent"];
  }
  if (self.hasContacts) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.contacts storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"contacts"];
  }
  if (self.hasGroups) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.groups storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"groups"];
  }
  if (self.hasRequest) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.request storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"request"];
  }
  for (SSKProtoSyncMessageRead* element in self.readArray) {
    NSMutableDictionary *elementDictionary = [NSMutableDictionary dictionary];
    [element storeInDictionary:elementDictionary];
    [dictionary setObject:[NSDictionary dictionaryWithDictionary:elementDictionary] forKey:@"read"];
  }
  if (self.hasBlocked) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.blocked storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"blocked"];
  }
  if (self.hasVerified) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.verified storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"verified"];
  }
  if (self.hasPadding) {
    [dictionary setObject: self.padding forKey: @"padding"];
  }
  if (self.hasConfiguration) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.configuration storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"configuration"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessage class]]) {
    return NO;
  }
  SSKProtoSyncMessage *otherMessage = other;
  return
      self.hasSent == otherMessage.hasSent &&
      (!self.hasSent || [self.sent isEqual:otherMessage.sent]) &&
      self.hasContacts == otherMessage.hasContacts &&
      (!self.hasContacts || [self.contacts isEqual:otherMessage.contacts]) &&
      self.hasGroups == otherMessage.hasGroups &&
      (!self.hasGroups || [self.groups isEqual:otherMessage.groups]) &&
      self.hasRequest == otherMessage.hasRequest &&
      (!self.hasRequest || [self.request isEqual:otherMessage.request]) &&
      [self.readArray isEqualToArray:otherMessage.readArray] &&
      self.hasBlocked == otherMessage.hasBlocked &&
      (!self.hasBlocked || [self.blocked isEqual:otherMessage.blocked]) &&
      self.hasVerified == otherMessage.hasVerified &&
      (!self.hasVerified || [self.verified isEqual:otherMessage.verified]) &&
      self.hasPadding == otherMessage.hasPadding &&
      (!self.hasPadding || [self.padding isEqual:otherMessage.padding]) &&
      self.hasConfiguration == otherMessage.hasConfiguration &&
      (!self.hasConfiguration || [self.configuration isEqual:otherMessage.configuration]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasSent) {
    hashCode = hashCode * 31 + [self.sent hash];
  }
  if (self.hasContacts) {
    hashCode = hashCode * 31 + [self.contacts hash];
  }
  if (self.hasGroups) {
    hashCode = hashCode * 31 + [self.groups hash];
  }
  if (self.hasRequest) {
    hashCode = hashCode * 31 + [self.request hash];
  }
  [self.readArray enumerateObjectsUsingBlock:^(SSKProtoSyncMessageRead *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasBlocked) {
    hashCode = hashCode * 31 + [self.blocked hash];
  }
  if (self.hasVerified) {
    hashCode = hashCode * 31 + [self.verified hash];
  }
  if (self.hasPadding) {
    hashCode = hashCode * 31 + [self.padding hash];
  }
  if (self.hasConfiguration) {
    hashCode = hashCode * 31 + [self.configuration hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageSent ()
@property (strong) NSString* destination;
@property UInt64 timestamp;
@property (strong) SSKProtoDataMessage* message;
@property UInt64 expirationStartTimestamp;
@end

@implementation SSKProtoSyncMessageSent

- (BOOL) hasDestination {
  return !!hasDestination_;
}
- (void) setHasDestination:(BOOL) _value_ {
  hasDestination_ = !!_value_;
}
@synthesize destination;
- (BOOL) hasTimestamp {
  return !!hasTimestamp_;
}
- (void) setHasTimestamp:(BOOL) _value_ {
  hasTimestamp_ = !!_value_;
}
@synthesize timestamp;
- (BOOL) hasMessage {
  return !!hasMessage_;
}
- (void) setHasMessage:(BOOL) _value_ {
  hasMessage_ = !!_value_;
}
@synthesize message;
- (BOOL) hasExpirationStartTimestamp {
  return !!hasExpirationStartTimestamp_;
}
- (void) setHasExpirationStartTimestamp:(BOOL) _value_ {
  hasExpirationStartTimestamp_ = !!_value_;
}
@synthesize expirationStartTimestamp;
- (instancetype) init {
  if ((self = [super init])) {
    self.destination = @"";
    self.timestamp = 0L;
    self.message = [SSKProtoDataMessage defaultInstance];
    self.expirationStartTimestamp = 0L;
  }
  return self;
}
static SSKProtoSyncMessageSent* defaultSSKProtoSyncMessageSentInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageSent class]) {
    defaultSSKProtoSyncMessageSentInstance = [[SSKProtoSyncMessageSent alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageSentInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageSentInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasDestination) {
    [output writeString:1 value:self.destination];
  }
  if (self.hasTimestamp) {
    [output writeUInt64:2 value:self.timestamp];
  }
  if (self.hasMessage) {
    [output writeMessage:3 value:self.message];
  }
  if (self.hasExpirationStartTimestamp) {
    [output writeUInt64:4 value:self.expirationStartTimestamp];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasDestination) {
    size_ += computeStringSize(1, self.destination);
  }
  if (self.hasTimestamp) {
    size_ += computeUInt64Size(2, self.timestamp);
  }
  if (self.hasMessage) {
    size_ += computeMessageSize(3, self.message);
  }
  if (self.hasExpirationStartTimestamp) {
    size_ += computeUInt64Size(4, self.expirationStartTimestamp);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageSent*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageSent*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageSent*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageSent*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageSent*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageSent*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageSent*)[[[SSKProtoSyncMessageSent builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageSentBuilder*) builder {
  return [[SSKProtoSyncMessageSentBuilder alloc] init];
}
+ (SSKProtoSyncMessageSentBuilder*) builderWithPrototype:(SSKProtoSyncMessageSent*) prototype {
  return [[SSKProtoSyncMessageSent builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageSentBuilder*) builder {
  return [SSKProtoSyncMessageSent builder];
}
- (SSKProtoSyncMessageSentBuilder*) toBuilder {
  return [SSKProtoSyncMessageSent builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasDestination) {
    [output appendFormat:@"%@%@: %@\n", indent, @"destination", self.destination];
  }
  if (self.hasTimestamp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"timestamp", [NSNumber numberWithLongLong:self.timestamp]];
  }
  if (self.hasMessage) {
    [output appendFormat:@"%@%@ {\n", indent, @"message"];
    [self.message writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasExpirationStartTimestamp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"expirationStartTimestamp", [NSNumber numberWithLongLong:self.expirationStartTimestamp]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasDestination) {
    [dictionary setObject: self.destination forKey: @"destination"];
  }
  if (self.hasTimestamp) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.timestamp] forKey: @"timestamp"];
  }
  if (self.hasMessage) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.message storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"message"];
  }
  if (self.hasExpirationStartTimestamp) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.expirationStartTimestamp] forKey: @"expirationStartTimestamp"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageSent class]]) {
    return NO;
  }
  SSKProtoSyncMessageSent *otherMessage = other;
  return
      self.hasDestination == otherMessage.hasDestination &&
      (!self.hasDestination || [self.destination isEqual:otherMessage.destination]) &&
      self.hasTimestamp == otherMessage.hasTimestamp &&
      (!self.hasTimestamp || self.timestamp == otherMessage.timestamp) &&
      self.hasMessage == otherMessage.hasMessage &&
      (!self.hasMessage || [self.message isEqual:otherMessage.message]) &&
      self.hasExpirationStartTimestamp == otherMessage.hasExpirationStartTimestamp &&
      (!self.hasExpirationStartTimestamp || self.expirationStartTimestamp == otherMessage.expirationStartTimestamp) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasDestination) {
    hashCode = hashCode * 31 + [self.destination hash];
  }
  if (self.hasTimestamp) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.timestamp] hash];
  }
  if (self.hasMessage) {
    hashCode = hashCode * 31 + [self.message hash];
  }
  if (self.hasExpirationStartTimestamp) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.expirationStartTimestamp] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageSentBuilder()
@property (strong) SSKProtoSyncMessageSent* resultSent;
@end

@implementation SSKProtoSyncMessageSentBuilder
@synthesize resultSent;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultSent = [[SSKProtoSyncMessageSent alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultSent;
}
- (SSKProtoSyncMessageSentBuilder*) clear {
  self.resultSent = [[SSKProtoSyncMessageSent alloc] init];
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) clone {
  return [SSKProtoSyncMessageSent builderWithPrototype:resultSent];
}
- (SSKProtoSyncMessageSent*) defaultInstance {
  return [SSKProtoSyncMessageSent defaultInstance];
}
- (SSKProtoSyncMessageSent*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageSent*) buildPartial {
  SSKProtoSyncMessageSent* returnMe = resultSent;
  self.resultSent = nil;
  return returnMe;
}
- (SSKProtoSyncMessageSentBuilder*) mergeFrom:(SSKProtoSyncMessageSent*) other {
  if (other == [SSKProtoSyncMessageSent defaultInstance]) {
    return self;
  }
  if (other.hasDestination) {
    [self setDestination:other.destination];
  }
  if (other.hasTimestamp) {
    [self setTimestamp:other.timestamp];
  }
  if (other.hasMessage) {
    [self mergeMessage:other.message];
  }
  if (other.hasExpirationStartTimestamp) {
    [self setExpirationStartTimestamp:other.expirationStartTimestamp];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageSentBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setDestination:[input readString]];
        break;
      }
      case 16: {
        [self setTimestamp:[input readUInt64]];
        break;
      }
      case 26: {
        SSKProtoDataMessageBuilder* subBuilder = [SSKProtoDataMessage builder];
        if (self.hasMessage) {
          [subBuilder mergeFrom:self.message];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setMessage:[subBuilder buildPartial]];
        break;
      }
      case 32: {
        [self setExpirationStartTimestamp:[input readUInt64]];
        break;
      }
    }
  }
}
- (BOOL) hasDestination {
  return resultSent.hasDestination;
}
- (NSString*) destination {
  return resultSent.destination;
}
- (SSKProtoSyncMessageSentBuilder*) setDestination:(NSString*) value {
  resultSent.hasDestination = YES;
  resultSent.destination = value;
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) clearDestination {
  resultSent.hasDestination = NO;
  resultSent.destination = @"";
  return self;
}
- (BOOL) hasTimestamp {
  return resultSent.hasTimestamp;
}
- (UInt64) timestamp {
  return resultSent.timestamp;
}
- (SSKProtoSyncMessageSentBuilder*) setTimestamp:(UInt64) value {
  resultSent.hasTimestamp = YES;
  resultSent.timestamp = value;
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) clearTimestamp {
  resultSent.hasTimestamp = NO;
  resultSent.timestamp = 0L;
  return self;
}
- (BOOL) hasMessage {
  return resultSent.hasMessage;
}
- (SSKProtoDataMessage*) message {
  return resultSent.message;
}
- (SSKProtoSyncMessageSentBuilder*) setMessage:(SSKProtoDataMessage*) value {
  resultSent.hasMessage = YES;
  resultSent.message = value;
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) setMessageBuilder:(SSKProtoDataMessageBuilder*) builderForValue {
  return [self setMessage:[builderForValue build]];
}
- (SSKProtoSyncMessageSentBuilder*) mergeMessage:(SSKProtoDataMessage*) value {
  if (resultSent.hasMessage &&
      resultSent.message != [SSKProtoDataMessage defaultInstance]) {
    resultSent.message =
      [[[SSKProtoDataMessage builderWithPrototype:resultSent.message] mergeFrom:value] buildPartial];
  } else {
    resultSent.message = value;
  }
  resultSent.hasMessage = YES;
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) clearMessage {
  resultSent.hasMessage = NO;
  resultSent.message = [SSKProtoDataMessage defaultInstance];
  return self;
}
- (BOOL) hasExpirationStartTimestamp {
  return resultSent.hasExpirationStartTimestamp;
}
- (UInt64) expirationStartTimestamp {
  return resultSent.expirationStartTimestamp;
}
- (SSKProtoSyncMessageSentBuilder*) setExpirationStartTimestamp:(UInt64) value {
  resultSent.hasExpirationStartTimestamp = YES;
  resultSent.expirationStartTimestamp = value;
  return self;
}
- (SSKProtoSyncMessageSentBuilder*) clearExpirationStartTimestamp {
  resultSent.hasExpirationStartTimestamp = NO;
  resultSent.expirationStartTimestamp = 0L;
  return self;
}
@end

@interface SSKProtoSyncMessageContacts ()
@property (strong) SSKProtoAttachmentPointer* blob;
@property BOOL isComplete;
@end

@implementation SSKProtoSyncMessageContacts

- (BOOL) hasBlob {
  return !!hasBlob_;
}
- (void) setHasBlob:(BOOL) _value_ {
  hasBlob_ = !!_value_;
}
@synthesize blob;
- (BOOL) hasIsComplete {
  return !!hasIsComplete_;
}
- (void) setHasIsComplete:(BOOL) _value_ {
  hasIsComplete_ = !!_value_;
}
- (BOOL) isComplete {
  return !!isComplete_;
}
- (void) setIsComplete:(BOOL) _value_ {
  isComplete_ = !!_value_;
}
- (instancetype) init {
  if ((self = [super init])) {
    self.blob = [SSKProtoAttachmentPointer defaultInstance];
    self.isComplete = NO;
  }
  return self;
}
static SSKProtoSyncMessageContacts* defaultSSKProtoSyncMessageContactsInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageContacts class]) {
    defaultSSKProtoSyncMessageContactsInstance = [[SSKProtoSyncMessageContacts alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageContactsInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageContactsInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasBlob) {
    [output writeMessage:1 value:self.blob];
  }
  if (self.hasIsComplete) {
    [output writeBool:2 value:self.isComplete];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasBlob) {
    size_ += computeMessageSize(1, self.blob);
  }
  if (self.hasIsComplete) {
    size_ += computeBoolSize(2, self.isComplete);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageContacts*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageContacts*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageContacts*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageContacts*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageContacts*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageContacts*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageContacts*)[[[SSKProtoSyncMessageContacts builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageContactsBuilder*) builder {
  return [[SSKProtoSyncMessageContactsBuilder alloc] init];
}
+ (SSKProtoSyncMessageContactsBuilder*) builderWithPrototype:(SSKProtoSyncMessageContacts*) prototype {
  return [[SSKProtoSyncMessageContacts builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageContactsBuilder*) builder {
  return [SSKProtoSyncMessageContacts builder];
}
- (SSKProtoSyncMessageContactsBuilder*) toBuilder {
  return [SSKProtoSyncMessageContacts builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasBlob) {
    [output appendFormat:@"%@%@ {\n", indent, @"blob"];
    [self.blob writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasIsComplete) {
    [output appendFormat:@"%@%@: %@\n", indent, @"isComplete", [NSNumber numberWithBool:self.isComplete]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasBlob) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.blob storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"blob"];
  }
  if (self.hasIsComplete) {
    [dictionary setObject: [NSNumber numberWithBool:self.isComplete] forKey: @"isComplete"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageContacts class]]) {
    return NO;
  }
  SSKProtoSyncMessageContacts *otherMessage = other;
  return
      self.hasBlob == otherMessage.hasBlob &&
      (!self.hasBlob || [self.blob isEqual:otherMessage.blob]) &&
      self.hasIsComplete == otherMessage.hasIsComplete &&
      (!self.hasIsComplete || self.isComplete == otherMessage.isComplete) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasBlob) {
    hashCode = hashCode * 31 + [self.blob hash];
  }
  if (self.hasIsComplete) {
    hashCode = hashCode * 31 + [[NSNumber numberWithBool:self.isComplete] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageContactsBuilder()
@property (strong) SSKProtoSyncMessageContacts* resultContacts;
@end

@implementation SSKProtoSyncMessageContactsBuilder
@synthesize resultContacts;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultContacts = [[SSKProtoSyncMessageContacts alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultContacts;
}
- (SSKProtoSyncMessageContactsBuilder*) clear {
  self.resultContacts = [[SSKProtoSyncMessageContacts alloc] init];
  return self;
}
- (SSKProtoSyncMessageContactsBuilder*) clone {
  return [SSKProtoSyncMessageContacts builderWithPrototype:resultContacts];
}
- (SSKProtoSyncMessageContacts*) defaultInstance {
  return [SSKProtoSyncMessageContacts defaultInstance];
}
- (SSKProtoSyncMessageContacts*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageContacts*) buildPartial {
  SSKProtoSyncMessageContacts* returnMe = resultContacts;
  self.resultContacts = nil;
  return returnMe;
}
- (SSKProtoSyncMessageContactsBuilder*) mergeFrom:(SSKProtoSyncMessageContacts*) other {
  if (other == [SSKProtoSyncMessageContacts defaultInstance]) {
    return self;
  }
  if (other.hasBlob) {
    [self mergeBlob:other.blob];
  }
  if (other.hasIsComplete) {
    [self setIsComplete:other.isComplete];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageContactsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageContactsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        if (self.hasBlob) {
          [subBuilder mergeFrom:self.blob];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setBlob:[subBuilder buildPartial]];
        break;
      }
      case 16: {
        [self setIsComplete:[input readBool]];
        break;
      }
    }
  }
}
- (BOOL) hasBlob {
  return resultContacts.hasBlob;
}
- (SSKProtoAttachmentPointer*) blob {
  return resultContacts.blob;
}
- (SSKProtoSyncMessageContactsBuilder*) setBlob:(SSKProtoAttachmentPointer*) value {
  resultContacts.hasBlob = YES;
  resultContacts.blob = value;
  return self;
}
- (SSKProtoSyncMessageContactsBuilder*) setBlobBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue {
  return [self setBlob:[builderForValue build]];
}
- (SSKProtoSyncMessageContactsBuilder*) mergeBlob:(SSKProtoAttachmentPointer*) value {
  if (resultContacts.hasBlob &&
      resultContacts.blob != [SSKProtoAttachmentPointer defaultInstance]) {
    resultContacts.blob =
      [[[SSKProtoAttachmentPointer builderWithPrototype:resultContacts.blob] mergeFrom:value] buildPartial];
  } else {
    resultContacts.blob = value;
  }
  resultContacts.hasBlob = YES;
  return self;
}
- (SSKProtoSyncMessageContactsBuilder*) clearBlob {
  resultContacts.hasBlob = NO;
  resultContacts.blob = [SSKProtoAttachmentPointer defaultInstance];
  return self;
}
- (BOOL) hasIsComplete {
  return resultContacts.hasIsComplete;
}
- (BOOL) isComplete {
  return resultContacts.isComplete;
}
- (SSKProtoSyncMessageContactsBuilder*) setIsComplete:(BOOL) value {
  resultContacts.hasIsComplete = YES;
  resultContacts.isComplete = value;
  return self;
}
- (SSKProtoSyncMessageContactsBuilder*) clearIsComplete {
  resultContacts.hasIsComplete = NO;
  resultContacts.isComplete = NO;
  return self;
}
@end

@interface SSKProtoSyncMessageGroups ()
@property (strong) SSKProtoAttachmentPointer* blob;
@end

@implementation SSKProtoSyncMessageGroups

- (BOOL) hasBlob {
  return !!hasBlob_;
}
- (void) setHasBlob:(BOOL) _value_ {
  hasBlob_ = !!_value_;
}
@synthesize blob;
- (instancetype) init {
  if ((self = [super init])) {
    self.blob = [SSKProtoAttachmentPointer defaultInstance];
  }
  return self;
}
static SSKProtoSyncMessageGroups* defaultSSKProtoSyncMessageGroupsInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageGroups class]) {
    defaultSSKProtoSyncMessageGroupsInstance = [[SSKProtoSyncMessageGroups alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageGroupsInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageGroupsInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasBlob) {
    [output writeMessage:1 value:self.blob];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasBlob) {
    size_ += computeMessageSize(1, self.blob);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageGroups*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageGroups*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageGroups*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageGroups*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageGroups*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageGroups*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageGroups*)[[[SSKProtoSyncMessageGroups builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageGroupsBuilder*) builder {
  return [[SSKProtoSyncMessageGroupsBuilder alloc] init];
}
+ (SSKProtoSyncMessageGroupsBuilder*) builderWithPrototype:(SSKProtoSyncMessageGroups*) prototype {
  return [[SSKProtoSyncMessageGroups builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageGroupsBuilder*) builder {
  return [SSKProtoSyncMessageGroups builder];
}
- (SSKProtoSyncMessageGroupsBuilder*) toBuilder {
  return [SSKProtoSyncMessageGroups builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasBlob) {
    [output appendFormat:@"%@%@ {\n", indent, @"blob"];
    [self.blob writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasBlob) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.blob storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"blob"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageGroups class]]) {
    return NO;
  }
  SSKProtoSyncMessageGroups *otherMessage = other;
  return
      self.hasBlob == otherMessage.hasBlob &&
      (!self.hasBlob || [self.blob isEqual:otherMessage.blob]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasBlob) {
    hashCode = hashCode * 31 + [self.blob hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageGroupsBuilder()
@property (strong) SSKProtoSyncMessageGroups* resultGroups;
@end

@implementation SSKProtoSyncMessageGroupsBuilder
@synthesize resultGroups;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultGroups = [[SSKProtoSyncMessageGroups alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultGroups;
}
- (SSKProtoSyncMessageGroupsBuilder*) clear {
  self.resultGroups = [[SSKProtoSyncMessageGroups alloc] init];
  return self;
}
- (SSKProtoSyncMessageGroupsBuilder*) clone {
  return [SSKProtoSyncMessageGroups builderWithPrototype:resultGroups];
}
- (SSKProtoSyncMessageGroups*) defaultInstance {
  return [SSKProtoSyncMessageGroups defaultInstance];
}
- (SSKProtoSyncMessageGroups*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageGroups*) buildPartial {
  SSKProtoSyncMessageGroups* returnMe = resultGroups;
  self.resultGroups = nil;
  return returnMe;
}
- (SSKProtoSyncMessageGroupsBuilder*) mergeFrom:(SSKProtoSyncMessageGroups*) other {
  if (other == [SSKProtoSyncMessageGroups defaultInstance]) {
    return self;
  }
  if (other.hasBlob) {
    [self mergeBlob:other.blob];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageGroupsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageGroupsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        if (self.hasBlob) {
          [subBuilder mergeFrom:self.blob];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setBlob:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasBlob {
  return resultGroups.hasBlob;
}
- (SSKProtoAttachmentPointer*) blob {
  return resultGroups.blob;
}
- (SSKProtoSyncMessageGroupsBuilder*) setBlob:(SSKProtoAttachmentPointer*) value {
  resultGroups.hasBlob = YES;
  resultGroups.blob = value;
  return self;
}
- (SSKProtoSyncMessageGroupsBuilder*) setBlobBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue {
  return [self setBlob:[builderForValue build]];
}
- (SSKProtoSyncMessageGroupsBuilder*) mergeBlob:(SSKProtoAttachmentPointer*) value {
  if (resultGroups.hasBlob &&
      resultGroups.blob != [SSKProtoAttachmentPointer defaultInstance]) {
    resultGroups.blob =
      [[[SSKProtoAttachmentPointer builderWithPrototype:resultGroups.blob] mergeFrom:value] buildPartial];
  } else {
    resultGroups.blob = value;
  }
  resultGroups.hasBlob = YES;
  return self;
}
- (SSKProtoSyncMessageGroupsBuilder*) clearBlob {
  resultGroups.hasBlob = NO;
  resultGroups.blob = [SSKProtoAttachmentPointer defaultInstance];
  return self;
}
@end

@interface SSKProtoSyncMessageBlocked ()
@property (strong) NSMutableArray * numbersArray;
@end

@implementation SSKProtoSyncMessageBlocked

@synthesize numbersArray;
@dynamic numbers;
- (instancetype) init {
  if ((self = [super init])) {
  }
  return self;
}
static SSKProtoSyncMessageBlocked* defaultSSKProtoSyncMessageBlockedInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageBlocked class]) {
    defaultSSKProtoSyncMessageBlockedInstance = [[SSKProtoSyncMessageBlocked alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageBlockedInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageBlockedInstance;
}
- (NSArray *)numbers {
  return numbersArray;
}
- (NSString*)numbersAtIndex:(NSUInteger)index {
  return [numbersArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  [self.numbersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    [output writeString:1 value:element];
  }];
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  {
    __block SInt32 dataSize = 0;
    const NSUInteger count = self.numbersArray.count;
    [self.numbersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
      dataSize += computeStringSizeNoTag(element);
    }];
    size_ += dataSize;
    size_ += (SInt32)(1 * count);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageBlocked*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageBlocked*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageBlocked*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageBlocked*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageBlocked*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageBlocked*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageBlocked*)[[[SSKProtoSyncMessageBlocked builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageBlockedBuilder*) builder {
  return [[SSKProtoSyncMessageBlockedBuilder alloc] init];
}
+ (SSKProtoSyncMessageBlockedBuilder*) builderWithPrototype:(SSKProtoSyncMessageBlocked*) prototype {
  return [[SSKProtoSyncMessageBlocked builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageBlockedBuilder*) builder {
  return [SSKProtoSyncMessageBlocked builder];
}
- (SSKProtoSyncMessageBlockedBuilder*) toBuilder {
  return [SSKProtoSyncMessageBlocked builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  [self.numbersArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@: %@\n", indent, @"numbers", obj];
  }];
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  [dictionary setObject:self.numbers forKey: @"numbers"];
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageBlocked class]]) {
    return NO;
  }
  SSKProtoSyncMessageBlocked *otherMessage = other;
  return
      [self.numbersArray isEqualToArray:otherMessage.numbersArray] &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  [self.numbersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageBlockedBuilder()
@property (strong) SSKProtoSyncMessageBlocked* resultBlocked;
@end

@implementation SSKProtoSyncMessageBlockedBuilder
@synthesize resultBlocked;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultBlocked = [[SSKProtoSyncMessageBlocked alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultBlocked;
}
- (SSKProtoSyncMessageBlockedBuilder*) clear {
  self.resultBlocked = [[SSKProtoSyncMessageBlocked alloc] init];
  return self;
}
- (SSKProtoSyncMessageBlockedBuilder*) clone {
  return [SSKProtoSyncMessageBlocked builderWithPrototype:resultBlocked];
}
- (SSKProtoSyncMessageBlocked*) defaultInstance {
  return [SSKProtoSyncMessageBlocked defaultInstance];
}
- (SSKProtoSyncMessageBlocked*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageBlocked*) buildPartial {
  SSKProtoSyncMessageBlocked* returnMe = resultBlocked;
  self.resultBlocked = nil;
  return returnMe;
}
- (SSKProtoSyncMessageBlockedBuilder*) mergeFrom:(SSKProtoSyncMessageBlocked*) other {
  if (other == [SSKProtoSyncMessageBlocked defaultInstance]) {
    return self;
  }
  if (other.numbersArray.count > 0) {
    if (resultBlocked.numbersArray == nil) {
      resultBlocked.numbersArray = [[NSMutableArray alloc] initWithArray:other.numbersArray];
    } else {
      [resultBlocked.numbersArray addObjectsFromArray:other.numbersArray];
    }
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageBlockedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageBlockedBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self addNumbers:[input readString]];
        break;
      }
    }
  }
}
- (NSMutableArray *)numbers {
  return resultBlocked.numbersArray;
}
- (NSString*)numbersAtIndex:(NSUInteger)index {
  return [resultBlocked numbersAtIndex:index];
}
- (SSKProtoSyncMessageBlockedBuilder *)addNumbers:(NSString*)value {
  if (resultBlocked.numbersArray == nil) {
    resultBlocked.numbersArray = [[NSMutableArray alloc]init];
  }
  [resultBlocked.numbersArray addObject:value];
  return self;
}
- (SSKProtoSyncMessageBlockedBuilder *)setNumbersArray:(NSArray *)array {
  resultBlocked.numbersArray = [[NSMutableArray alloc] initWithArray:array];
  return self;
}
- (SSKProtoSyncMessageBlockedBuilder *)clearNumbers {
  resultBlocked.numbersArray = nil;
  return self;
}
@end

@interface SSKProtoSyncMessageRequest ()
@property SSKProtoSyncMessageRequestType type;
@end

@implementation SSKProtoSyncMessageRequest

- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (instancetype) init {
  if ((self = [super init])) {
    self.type = SSKProtoSyncMessageRequestTypeUnknown;
  }
  return self;
}
static SSKProtoSyncMessageRequest* defaultSSKProtoSyncMessageRequestInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageRequest class]) {
    defaultSSKProtoSyncMessageRequestInstance = [[SSKProtoSyncMessageRequest alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageRequestInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageRequestInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasType) {
    [output writeEnum:1 value:self.type];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasType) {
    size_ += computeEnumSize(1, self.type);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageRequest*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageRequest*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageRequest*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageRequest*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageRequest*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageRequest*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRequest*)[[[SSKProtoSyncMessageRequest builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageRequestBuilder*) builder {
  return [[SSKProtoSyncMessageRequestBuilder alloc] init];
}
+ (SSKProtoSyncMessageRequestBuilder*) builderWithPrototype:(SSKProtoSyncMessageRequest*) prototype {
  return [[SSKProtoSyncMessageRequest builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageRequestBuilder*) builder {
  return [SSKProtoSyncMessageRequest builder];
}
- (SSKProtoSyncMessageRequestBuilder*) toBuilder {
  return [SSKProtoSyncMessageRequest builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoSyncMessageRequestType(self.type)];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageRequest class]]) {
    return NO;
  }
  SSKProtoSyncMessageRequest *otherMessage = other;
  return
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoSyncMessageRequestTypeIsValidValue(SSKProtoSyncMessageRequestType value) {
  switch (value) {
    case SSKProtoSyncMessageRequestTypeUnknown:
    case SSKProtoSyncMessageRequestTypeContacts:
    case SSKProtoSyncMessageRequestTypeGroups:
    case SSKProtoSyncMessageRequestTypeBlocked:
    case SSKProtoSyncMessageRequestTypeConfiguration:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoSyncMessageRequestType(SSKProtoSyncMessageRequestType value) {
  switch (value) {
    case SSKProtoSyncMessageRequestTypeUnknown:
      return @"SSKProtoSyncMessageRequestTypeUnknown";
    case SSKProtoSyncMessageRequestTypeContacts:
      return @"SSKProtoSyncMessageRequestTypeContacts";
    case SSKProtoSyncMessageRequestTypeGroups:
      return @"SSKProtoSyncMessageRequestTypeGroups";
    case SSKProtoSyncMessageRequestTypeBlocked:
      return @"SSKProtoSyncMessageRequestTypeBlocked";
    case SSKProtoSyncMessageRequestTypeConfiguration:
      return @"SSKProtoSyncMessageRequestTypeConfiguration";
    default:
      return nil;
  }
}

@interface SSKProtoSyncMessageRequestBuilder()
@property (strong) SSKProtoSyncMessageRequest* resultRequest;
@end

@implementation SSKProtoSyncMessageRequestBuilder
@synthesize resultRequest;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultRequest = [[SSKProtoSyncMessageRequest alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultRequest;
}
- (SSKProtoSyncMessageRequestBuilder*) clear {
  self.resultRequest = [[SSKProtoSyncMessageRequest alloc] init];
  return self;
}
- (SSKProtoSyncMessageRequestBuilder*) clone {
  return [SSKProtoSyncMessageRequest builderWithPrototype:resultRequest];
}
- (SSKProtoSyncMessageRequest*) defaultInstance {
  return [SSKProtoSyncMessageRequest defaultInstance];
}
- (SSKProtoSyncMessageRequest*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageRequest*) buildPartial {
  SSKProtoSyncMessageRequest* returnMe = resultRequest;
  self.resultRequest = nil;
  return returnMe;
}
- (SSKProtoSyncMessageRequestBuilder*) mergeFrom:(SSKProtoSyncMessageRequest*) other {
  if (other == [SSKProtoSyncMessageRequest defaultInstance]) {
    return self;
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageRequestBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageRequestBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        SSKProtoSyncMessageRequestType value = (SSKProtoSyncMessageRequestType)[input readEnum];
        if (SSKProtoSyncMessageRequestTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:1 value:value];
        }
        break;
      }
    }
  }
}
- (BOOL) hasType {
  return resultRequest.hasType;
}
- (SSKProtoSyncMessageRequestType) type {
  return resultRequest.type;
}
- (SSKProtoSyncMessageRequestBuilder*) setType:(SSKProtoSyncMessageRequestType) value {
  resultRequest.hasType = YES;
  resultRequest.type = value;
  return self;
}
- (SSKProtoSyncMessageRequestBuilder*) clearType {
  resultRequest.hasType = NO;
  resultRequest.type = SSKProtoSyncMessageRequestTypeUnknown;
  return self;
}
@end

@interface SSKProtoSyncMessageRead ()
@property (strong) NSString* sender;
@property UInt64 timestamp;
@end

@implementation SSKProtoSyncMessageRead

- (BOOL) hasSender {
  return !!hasSender_;
}
- (void) setHasSender:(BOOL) _value_ {
  hasSender_ = !!_value_;
}
@synthesize sender;
- (BOOL) hasTimestamp {
  return !!hasTimestamp_;
}
- (void) setHasTimestamp:(BOOL) _value_ {
  hasTimestamp_ = !!_value_;
}
@synthesize timestamp;
- (instancetype) init {
  if ((self = [super init])) {
    self.sender = @"";
    self.timestamp = 0L;
  }
  return self;
}
static SSKProtoSyncMessageRead* defaultSSKProtoSyncMessageReadInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageRead class]) {
    defaultSSKProtoSyncMessageReadInstance = [[SSKProtoSyncMessageRead alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageReadInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageReadInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasSender) {
    [output writeString:1 value:self.sender];
  }
  if (self.hasTimestamp) {
    [output writeUInt64:2 value:self.timestamp];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasSender) {
    size_ += computeStringSize(1, self.sender);
  }
  if (self.hasTimestamp) {
    size_ += computeUInt64Size(2, self.timestamp);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageRead*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageRead*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageRead*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageRead*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageRead*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageRead*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageRead*)[[[SSKProtoSyncMessageRead builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageReadBuilder*) builder {
  return [[SSKProtoSyncMessageReadBuilder alloc] init];
}
+ (SSKProtoSyncMessageReadBuilder*) builderWithPrototype:(SSKProtoSyncMessageRead*) prototype {
  return [[SSKProtoSyncMessageRead builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageReadBuilder*) builder {
  return [SSKProtoSyncMessageRead builder];
}
- (SSKProtoSyncMessageReadBuilder*) toBuilder {
  return [SSKProtoSyncMessageRead builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasSender) {
    [output appendFormat:@"%@%@: %@\n", indent, @"sender", self.sender];
  }
  if (self.hasTimestamp) {
    [output appendFormat:@"%@%@: %@\n", indent, @"timestamp", [NSNumber numberWithLongLong:self.timestamp]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasSender) {
    [dictionary setObject: self.sender forKey: @"sender"];
  }
  if (self.hasTimestamp) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.timestamp] forKey: @"timestamp"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageRead class]]) {
    return NO;
  }
  SSKProtoSyncMessageRead *otherMessage = other;
  return
      self.hasSender == otherMessage.hasSender &&
      (!self.hasSender || [self.sender isEqual:otherMessage.sender]) &&
      self.hasTimestamp == otherMessage.hasTimestamp &&
      (!self.hasTimestamp || self.timestamp == otherMessage.timestamp) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasSender) {
    hashCode = hashCode * 31 + [self.sender hash];
  }
  if (self.hasTimestamp) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.timestamp] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageReadBuilder()
@property (strong) SSKProtoSyncMessageRead* resultRead;
@end

@implementation SSKProtoSyncMessageReadBuilder
@synthesize resultRead;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultRead = [[SSKProtoSyncMessageRead alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultRead;
}
- (SSKProtoSyncMessageReadBuilder*) clear {
  self.resultRead = [[SSKProtoSyncMessageRead alloc] init];
  return self;
}
- (SSKProtoSyncMessageReadBuilder*) clone {
  return [SSKProtoSyncMessageRead builderWithPrototype:resultRead];
}
- (SSKProtoSyncMessageRead*) defaultInstance {
  return [SSKProtoSyncMessageRead defaultInstance];
}
- (SSKProtoSyncMessageRead*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageRead*) buildPartial {
  SSKProtoSyncMessageRead* returnMe = resultRead;
  self.resultRead = nil;
  return returnMe;
}
- (SSKProtoSyncMessageReadBuilder*) mergeFrom:(SSKProtoSyncMessageRead*) other {
  if (other == [SSKProtoSyncMessageRead defaultInstance]) {
    return self;
  }
  if (other.hasSender) {
    [self setSender:other.sender];
  }
  if (other.hasTimestamp) {
    [self setTimestamp:other.timestamp];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageReadBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageReadBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setSender:[input readString]];
        break;
      }
      case 16: {
        [self setTimestamp:[input readUInt64]];
        break;
      }
    }
  }
}
- (BOOL) hasSender {
  return resultRead.hasSender;
}
- (NSString*) sender {
  return resultRead.sender;
}
- (SSKProtoSyncMessageReadBuilder*) setSender:(NSString*) value {
  resultRead.hasSender = YES;
  resultRead.sender = value;
  return self;
}
- (SSKProtoSyncMessageReadBuilder*) clearSender {
  resultRead.hasSender = NO;
  resultRead.sender = @"";
  return self;
}
- (BOOL) hasTimestamp {
  return resultRead.hasTimestamp;
}
- (UInt64) timestamp {
  return resultRead.timestamp;
}
- (SSKProtoSyncMessageReadBuilder*) setTimestamp:(UInt64) value {
  resultRead.hasTimestamp = YES;
  resultRead.timestamp = value;
  return self;
}
- (SSKProtoSyncMessageReadBuilder*) clearTimestamp {
  resultRead.hasTimestamp = NO;
  resultRead.timestamp = 0L;
  return self;
}
@end

@interface SSKProtoSyncMessageConfiguration ()
@property BOOL readReceipts;
@end

@implementation SSKProtoSyncMessageConfiguration

- (BOOL) hasReadReceipts {
  return !!hasReadReceipts_;
}
- (void) setHasReadReceipts:(BOOL) _value_ {
  hasReadReceipts_ = !!_value_;
}
- (BOOL) readReceipts {
  return !!readReceipts_;
}
- (void) setReadReceipts:(BOOL) _value_ {
  readReceipts_ = !!_value_;
}
- (instancetype) init {
  if ((self = [super init])) {
    self.readReceipts = NO;
  }
  return self;
}
static SSKProtoSyncMessageConfiguration* defaultSSKProtoSyncMessageConfigurationInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoSyncMessageConfiguration class]) {
    defaultSSKProtoSyncMessageConfigurationInstance = [[SSKProtoSyncMessageConfiguration alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageConfigurationInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoSyncMessageConfigurationInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasReadReceipts) {
    [output writeBool:1 value:self.readReceipts];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasReadReceipts) {
    size_ += computeBoolSize(1, self.readReceipts);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoSyncMessageConfiguration*) parseFromData:(NSData*) data {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromData:data] build];
}
+ (SSKProtoSyncMessageConfiguration*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageConfiguration*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromInputStream:input] build];
}
+ (SSKProtoSyncMessageConfiguration*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageConfiguration*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoSyncMessageConfiguration*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoSyncMessageConfiguration*)[[[SSKProtoSyncMessageConfiguration builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoSyncMessageConfigurationBuilder*) builder {
  return [[SSKProtoSyncMessageConfigurationBuilder alloc] init];
}
+ (SSKProtoSyncMessageConfigurationBuilder*) builderWithPrototype:(SSKProtoSyncMessageConfiguration*) prototype {
  return [[SSKProtoSyncMessageConfiguration builder] mergeFrom:prototype];
}
- (SSKProtoSyncMessageConfigurationBuilder*) builder {
  return [SSKProtoSyncMessageConfiguration builder];
}
- (SSKProtoSyncMessageConfigurationBuilder*) toBuilder {
  return [SSKProtoSyncMessageConfiguration builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasReadReceipts) {
    [output appendFormat:@"%@%@: %@\n", indent, @"readReceipts", [NSNumber numberWithBool:self.readReceipts]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasReadReceipts) {
    [dictionary setObject: [NSNumber numberWithBool:self.readReceipts] forKey: @"readReceipts"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoSyncMessageConfiguration class]]) {
    return NO;
  }
  SSKProtoSyncMessageConfiguration *otherMessage = other;
  return
      self.hasReadReceipts == otherMessage.hasReadReceipts &&
      (!self.hasReadReceipts || self.readReceipts == otherMessage.readReceipts) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasReadReceipts) {
    hashCode = hashCode * 31 + [[NSNumber numberWithBool:self.readReceipts] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoSyncMessageConfigurationBuilder()
@property (strong) SSKProtoSyncMessageConfiguration* resultConfiguration;
@end

@implementation SSKProtoSyncMessageConfigurationBuilder
@synthesize resultConfiguration;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultConfiguration = [[SSKProtoSyncMessageConfiguration alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultConfiguration;
}
- (SSKProtoSyncMessageConfigurationBuilder*) clear {
  self.resultConfiguration = [[SSKProtoSyncMessageConfiguration alloc] init];
  return self;
}
- (SSKProtoSyncMessageConfigurationBuilder*) clone {
  return [SSKProtoSyncMessageConfiguration builderWithPrototype:resultConfiguration];
}
- (SSKProtoSyncMessageConfiguration*) defaultInstance {
  return [SSKProtoSyncMessageConfiguration defaultInstance];
}
- (SSKProtoSyncMessageConfiguration*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessageConfiguration*) buildPartial {
  SSKProtoSyncMessageConfiguration* returnMe = resultConfiguration;
  self.resultConfiguration = nil;
  return returnMe;
}
- (SSKProtoSyncMessageConfigurationBuilder*) mergeFrom:(SSKProtoSyncMessageConfiguration*) other {
  if (other == [SSKProtoSyncMessageConfiguration defaultInstance]) {
    return self;
  }
  if (other.hasReadReceipts) {
    [self setReadReceipts:other.readReceipts];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageConfigurationBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageConfigurationBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 8: {
        [self setReadReceipts:[input readBool]];
        break;
      }
    }
  }
}
- (BOOL) hasReadReceipts {
  return resultConfiguration.hasReadReceipts;
}
- (BOOL) readReceipts {
  return resultConfiguration.readReceipts;
}
- (SSKProtoSyncMessageConfigurationBuilder*) setReadReceipts:(BOOL) value {
  resultConfiguration.hasReadReceipts = YES;
  resultConfiguration.readReceipts = value;
  return self;
}
- (SSKProtoSyncMessageConfigurationBuilder*) clearReadReceipts {
  resultConfiguration.hasReadReceipts = NO;
  resultConfiguration.readReceipts = NO;
  return self;
}
@end

@interface SSKProtoSyncMessageBuilder()
@property (strong) SSKProtoSyncMessage* resultSyncMessage;
@end

@implementation SSKProtoSyncMessageBuilder
@synthesize resultSyncMessage;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultSyncMessage = [[SSKProtoSyncMessage alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultSyncMessage;
}
- (SSKProtoSyncMessageBuilder*) clear {
  self.resultSyncMessage = [[SSKProtoSyncMessage alloc] init];
  return self;
}
- (SSKProtoSyncMessageBuilder*) clone {
  return [SSKProtoSyncMessage builderWithPrototype:resultSyncMessage];
}
- (SSKProtoSyncMessage*) defaultInstance {
  return [SSKProtoSyncMessage defaultInstance];
}
- (SSKProtoSyncMessage*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoSyncMessage*) buildPartial {
  SSKProtoSyncMessage* returnMe = resultSyncMessage;
  self.resultSyncMessage = nil;
  return returnMe;
}
- (SSKProtoSyncMessageBuilder*) mergeFrom:(SSKProtoSyncMessage*) other {
  if (other == [SSKProtoSyncMessage defaultInstance]) {
    return self;
  }
  if (other.hasSent) {
    [self mergeSent:other.sent];
  }
  if (other.hasContacts) {
    [self mergeContacts:other.contacts];
  }
  if (other.hasGroups) {
    [self mergeGroups:other.groups];
  }
  if (other.hasRequest) {
    [self mergeRequest:other.request];
  }
  if (other.readArray.count > 0) {
    if (resultSyncMessage.readArray == nil) {
      resultSyncMessage.readArray = [[NSMutableArray alloc] initWithArray:other.readArray];
    } else {
      [resultSyncMessage.readArray addObjectsFromArray:other.readArray];
    }
  }
  if (other.hasBlocked) {
    [self mergeBlocked:other.blocked];
  }
  if (other.hasVerified) {
    [self mergeVerified:other.verified];
  }
  if (other.hasConfiguration) {
    [self mergeConfiguration:other.configuration];
  }
  if (other.hasPadding) {
    [self setPadding:other.padding];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoSyncMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoSyncMessageBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        SSKProtoSyncMessageSentBuilder* subBuilder = [SSKProtoSyncMessageSent builder];
        if (self.hasSent) {
          [subBuilder mergeFrom:self.sent];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setSent:[subBuilder buildPartial]];
        break;
      }
      case 18: {
        SSKProtoSyncMessageContactsBuilder* subBuilder = [SSKProtoSyncMessageContacts builder];
        if (self.hasContacts) {
          [subBuilder mergeFrom:self.contacts];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setContacts:[subBuilder buildPartial]];
        break;
      }
      case 26: {
        SSKProtoSyncMessageGroupsBuilder* subBuilder = [SSKProtoSyncMessageGroups builder];
        if (self.hasGroups) {
          [subBuilder mergeFrom:self.groups];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setGroups:[subBuilder buildPartial]];
        break;
      }
      case 34: {
        SSKProtoSyncMessageRequestBuilder* subBuilder = [SSKProtoSyncMessageRequest builder];
        if (self.hasRequest) {
          [subBuilder mergeFrom:self.request];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setRequest:[subBuilder buildPartial]];
        break;
      }
      case 42: {
        SSKProtoSyncMessageReadBuilder* subBuilder = [SSKProtoSyncMessageRead builder];
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self addRead:[subBuilder buildPartial]];
        break;
      }
      case 50: {
        SSKProtoSyncMessageBlockedBuilder* subBuilder = [SSKProtoSyncMessageBlocked builder];
        if (self.hasBlocked) {
          [subBuilder mergeFrom:self.blocked];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setBlocked:[subBuilder buildPartial]];
        break;
      }
      case 58: {
        SSKProtoVerifiedBuilder* subBuilder = [SSKProtoVerified builder];
        if (self.hasVerified) {
          [subBuilder mergeFrom:self.verified];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setVerified:[subBuilder buildPartial]];
        break;
      }
      case 66: {
        [self setPadding:[input readData]];
        break;
      }
      case 74: {
        SSKProtoSyncMessageConfigurationBuilder* subBuilder = [SSKProtoSyncMessageConfiguration builder];
        if (self.hasConfiguration) {
          [subBuilder mergeFrom:self.configuration];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setConfiguration:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasSent {
  return resultSyncMessage.hasSent;
}
- (SSKProtoSyncMessageSent*) sent {
  return resultSyncMessage.sent;
}
- (SSKProtoSyncMessageBuilder*) setSent:(SSKProtoSyncMessageSent*) value {
  resultSyncMessage.hasSent = YES;
  resultSyncMessage.sent = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setSentBuilder:(SSKProtoSyncMessageSentBuilder*) builderForValue {
  return [self setSent:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeSent:(SSKProtoSyncMessageSent*) value {
  if (resultSyncMessage.hasSent &&
      resultSyncMessage.sent != [SSKProtoSyncMessageSent defaultInstance]) {
    resultSyncMessage.sent =
      [[[SSKProtoSyncMessageSent builderWithPrototype:resultSyncMessage.sent] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.sent = value;
  }
  resultSyncMessage.hasSent = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearSent {
  resultSyncMessage.hasSent = NO;
  resultSyncMessage.sent = [SSKProtoSyncMessageSent defaultInstance];
  return self;
}
- (BOOL) hasContacts {
  return resultSyncMessage.hasContacts;
}
- (SSKProtoSyncMessageContacts*) contacts {
  return resultSyncMessage.contacts;
}
- (SSKProtoSyncMessageBuilder*) setContacts:(SSKProtoSyncMessageContacts*) value {
  resultSyncMessage.hasContacts = YES;
  resultSyncMessage.contacts = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setContactsBuilder:(SSKProtoSyncMessageContactsBuilder*) builderForValue {
  return [self setContacts:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeContacts:(SSKProtoSyncMessageContacts*) value {
  if (resultSyncMessage.hasContacts &&
      resultSyncMessage.contacts != [SSKProtoSyncMessageContacts defaultInstance]) {
    resultSyncMessage.contacts =
      [[[SSKProtoSyncMessageContacts builderWithPrototype:resultSyncMessage.contacts] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.contacts = value;
  }
  resultSyncMessage.hasContacts = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearContacts {
  resultSyncMessage.hasContacts = NO;
  resultSyncMessage.contacts = [SSKProtoSyncMessageContacts defaultInstance];
  return self;
}
- (BOOL) hasGroups {
  return resultSyncMessage.hasGroups;
}
- (SSKProtoSyncMessageGroups*) groups {
  return resultSyncMessage.groups;
}
- (SSKProtoSyncMessageBuilder*) setGroups:(SSKProtoSyncMessageGroups*) value {
  resultSyncMessage.hasGroups = YES;
  resultSyncMessage.groups = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setGroupsBuilder:(SSKProtoSyncMessageGroupsBuilder*) builderForValue {
  return [self setGroups:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeGroups:(SSKProtoSyncMessageGroups*) value {
  if (resultSyncMessage.hasGroups &&
      resultSyncMessage.groups != [SSKProtoSyncMessageGroups defaultInstance]) {
    resultSyncMessage.groups =
      [[[SSKProtoSyncMessageGroups builderWithPrototype:resultSyncMessage.groups] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.groups = value;
  }
  resultSyncMessage.hasGroups = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearGroups {
  resultSyncMessage.hasGroups = NO;
  resultSyncMessage.groups = [SSKProtoSyncMessageGroups defaultInstance];
  return self;
}
- (BOOL) hasRequest {
  return resultSyncMessage.hasRequest;
}
- (SSKProtoSyncMessageRequest*) request {
  return resultSyncMessage.request;
}
- (SSKProtoSyncMessageBuilder*) setRequest:(SSKProtoSyncMessageRequest*) value {
  resultSyncMessage.hasRequest = YES;
  resultSyncMessage.request = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setRequestBuilder:(SSKProtoSyncMessageRequestBuilder*) builderForValue {
  return [self setRequest:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeRequest:(SSKProtoSyncMessageRequest*) value {
  if (resultSyncMessage.hasRequest &&
      resultSyncMessage.request != [SSKProtoSyncMessageRequest defaultInstance]) {
    resultSyncMessage.request =
      [[[SSKProtoSyncMessageRequest builderWithPrototype:resultSyncMessage.request] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.request = value;
  }
  resultSyncMessage.hasRequest = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearRequest {
  resultSyncMessage.hasRequest = NO;
  resultSyncMessage.request = [SSKProtoSyncMessageRequest defaultInstance];
  return self;
}
- (NSMutableArray<SSKProtoSyncMessageRead*> *)read {
  return resultSyncMessage.readArray;
}
- (SSKProtoSyncMessageRead*)readAtIndex:(NSUInteger)index {
  return [resultSyncMessage readAtIndex:index];
}
- (SSKProtoSyncMessageBuilder *)addRead:(SSKProtoSyncMessageRead*)value {
  if (resultSyncMessage.readArray == nil) {
    resultSyncMessage.readArray = [[NSMutableArray alloc]init];
  }
  [resultSyncMessage.readArray addObject:value];
  return self;
}
- (SSKProtoSyncMessageBuilder *)setReadArray:(NSArray<SSKProtoSyncMessageRead*> *)array {
  resultSyncMessage.readArray = [[NSMutableArray alloc]initWithArray:array];
  return self;
}
- (SSKProtoSyncMessageBuilder *)clearRead {
  resultSyncMessage.readArray = nil;
  return self;
}
- (BOOL) hasBlocked {
  return resultSyncMessage.hasBlocked;
}
- (SSKProtoSyncMessageBlocked*) blocked {
  return resultSyncMessage.blocked;
}
- (SSKProtoSyncMessageBuilder*) setBlocked:(SSKProtoSyncMessageBlocked*) value {
  resultSyncMessage.hasBlocked = YES;
  resultSyncMessage.blocked = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setBlockedBuilder:(SSKProtoSyncMessageBlockedBuilder*) builderForValue {
  return [self setBlocked:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeBlocked:(SSKProtoSyncMessageBlocked*) value {
  if (resultSyncMessage.hasBlocked &&
      resultSyncMessage.blocked != [SSKProtoSyncMessageBlocked defaultInstance]) {
    resultSyncMessage.blocked =
      [[[SSKProtoSyncMessageBlocked builderWithPrototype:resultSyncMessage.blocked] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.blocked = value;
  }
  resultSyncMessage.hasBlocked = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearBlocked {
  resultSyncMessage.hasBlocked = NO;
  resultSyncMessage.blocked = [SSKProtoSyncMessageBlocked defaultInstance];
  return self;
}
- (BOOL) hasVerified {
  return resultSyncMessage.hasVerified;
}
- (SSKProtoVerified*) verified {
  return resultSyncMessage.verified;
}
- (SSKProtoSyncMessageBuilder*) setVerified:(SSKProtoVerified*) value {
  resultSyncMessage.hasVerified = YES;
  resultSyncMessage.verified = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setVerifiedBuilder:(SSKProtoVerifiedBuilder*) builderForValue {
  return [self setVerified:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeVerified:(SSKProtoVerified*) value {
  if (resultSyncMessage.hasVerified &&
      resultSyncMessage.verified != [SSKProtoVerified defaultInstance]) {
    resultSyncMessage.verified =
      [[[SSKProtoVerified builderWithPrototype:resultSyncMessage.verified] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.verified = value;
  }
  resultSyncMessage.hasVerified = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearVerified {
  resultSyncMessage.hasVerified = NO;
  resultSyncMessage.verified = [SSKProtoVerified defaultInstance];
  return self;
}
- (BOOL) hasConfiguration {
  return resultSyncMessage.hasConfiguration;
}
- (SSKProtoSyncMessageConfiguration*) configuration {
  return resultSyncMessage.configuration;
}
- (SSKProtoSyncMessageBuilder*) setConfiguration:(SSKProtoSyncMessageConfiguration*) value {
  resultSyncMessage.hasConfiguration = YES;
  resultSyncMessage.configuration = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) setConfigurationBuilder:(SSKProtoSyncMessageConfigurationBuilder*) builderForValue {
  return [self setConfiguration:[builderForValue build]];
}
- (SSKProtoSyncMessageBuilder*) mergeConfiguration:(SSKProtoSyncMessageConfiguration*) value {
  if (resultSyncMessage.hasConfiguration &&
      resultSyncMessage.configuration != [SSKProtoSyncMessageConfiguration defaultInstance]) {
    resultSyncMessage.configuration =
      [[[SSKProtoSyncMessageConfiguration builderWithPrototype:resultSyncMessage.configuration] mergeFrom:value] buildPartial];
  } else {
    resultSyncMessage.configuration = value;
  }
  resultSyncMessage.hasConfiguration = YES;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearConfiguration {
  resultSyncMessage.hasConfiguration = NO;
  resultSyncMessage.configuration = [SSKProtoSyncMessageConfiguration defaultInstance];
  return self;
}
- (BOOL) hasPadding {
  return resultSyncMessage.hasPadding;
}
- (NSData*) padding {
  return resultSyncMessage.padding;
}
- (SSKProtoSyncMessageBuilder*) setPadding:(NSData*) value {
  resultSyncMessage.hasPadding = YES;
  resultSyncMessage.padding = value;
  return self;
}
- (SSKProtoSyncMessageBuilder*) clearPadding {
  resultSyncMessage.hasPadding = NO;
  resultSyncMessage.padding = [NSData data];
  return self;
}
@end

@interface SSKProtoAttachmentPointer ()
@property UInt64 id;
@property (strong) NSString* contentType;
@property (strong) NSData* key;
@property UInt32 size;
@property (strong) NSData* thumbnail;
@property (strong) NSData* digest;
@property (strong) NSString* fileName;
@property UInt32 flags;
@property UInt32 width;
@property UInt32 height;
@end

@implementation SSKProtoAttachmentPointer

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasContentType {
  return !!hasContentType_;
}
- (void) setHasContentType:(BOOL) _value_ {
  hasContentType_ = !!_value_;
}
@synthesize contentType;
- (BOOL) hasKey {
  return !!hasKey_;
}
- (void) setHasKey:(BOOL) _value_ {
  hasKey_ = !!_value_;
}
@synthesize key;
- (BOOL) hasSize {
  return !!hasSize_;
}
- (void) setHasSize:(BOOL) _value_ {
  hasSize_ = !!_value_;
}
@synthesize size;
- (BOOL) hasThumbnail {
  return !!hasThumbnail_;
}
- (void) setHasThumbnail:(BOOL) _value_ {
  hasThumbnail_ = !!_value_;
}
@synthesize thumbnail;
- (BOOL) hasDigest {
  return !!hasDigest_;
}
- (void) setHasDigest:(BOOL) _value_ {
  hasDigest_ = !!_value_;
}
@synthesize digest;
- (BOOL) hasFileName {
  return !!hasFileName_;
}
- (void) setHasFileName:(BOOL) _value_ {
  hasFileName_ = !!_value_;
}
@synthesize fileName;
- (BOOL) hasFlags {
  return !!hasFlags_;
}
- (void) setHasFlags:(BOOL) _value_ {
  hasFlags_ = !!_value_;
}
@synthesize flags;
- (BOOL) hasWidth {
  return !!hasWidth_;
}
- (void) setHasWidth:(BOOL) _value_ {
  hasWidth_ = !!_value_;
}
@synthesize width;
- (BOOL) hasHeight {
  return !!hasHeight_;
}
- (void) setHasHeight:(BOOL) _value_ {
  hasHeight_ = !!_value_;
}
@synthesize height;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = 0L;
    self.contentType = @"";
    self.key = [NSData data];
    self.size = 0;
    self.thumbnail = [NSData data];
    self.digest = [NSData data];
    self.fileName = @"";
    self.flags = 0;
    self.width = 0;
    self.height = 0;
  }
  return self;
}
static SSKProtoAttachmentPointer* defaultSSKProtoAttachmentPointerInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoAttachmentPointer class]) {
    defaultSSKProtoAttachmentPointerInstance = [[SSKProtoAttachmentPointer alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoAttachmentPointerInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoAttachmentPointerInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeFixed64:1 value:self.id];
  }
  if (self.hasContentType) {
    [output writeString:2 value:self.contentType];
  }
  if (self.hasKey) {
    [output writeData:3 value:self.key];
  }
  if (self.hasSize) {
    [output writeUInt32:4 value:self.size];
  }
  if (self.hasThumbnail) {
    [output writeData:5 value:self.thumbnail];
  }
  if (self.hasDigest) {
    [output writeData:6 value:self.digest];
  }
  if (self.hasFileName) {
    [output writeString:7 value:self.fileName];
  }
  if (self.hasFlags) {
    [output writeUInt32:8 value:self.flags];
  }
  if (self.hasWidth) {
    [output writeUInt32:9 value:self.width];
  }
  if (self.hasHeight) {
    [output writeUInt32:10 value:self.height];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeFixed64Size(1, self.id);
  }
  if (self.hasContentType) {
    size_ += computeStringSize(2, self.contentType);
  }
  if (self.hasKey) {
    size_ += computeDataSize(3, self.key);
  }
  if (self.hasSize) {
    size_ += computeUInt32Size(4, self.size);
  }
  if (self.hasThumbnail) {
    size_ += computeDataSize(5, self.thumbnail);
  }
  if (self.hasDigest) {
    size_ += computeDataSize(6, self.digest);
  }
  if (self.hasFileName) {
    size_ += computeStringSize(7, self.fileName);
  }
  if (self.hasFlags) {
    size_ += computeUInt32Size(8, self.flags);
  }
  if (self.hasWidth) {
    size_ += computeUInt32Size(9, self.width);
  }
  if (self.hasHeight) {
    size_ += computeUInt32Size(10, self.height);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoAttachmentPointer*) parseFromData:(NSData*) data {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromData:data] build];
}
+ (SSKProtoAttachmentPointer*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoAttachmentPointer*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromInputStream:input] build];
}
+ (SSKProtoAttachmentPointer*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoAttachmentPointer*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoAttachmentPointer*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoAttachmentPointer*)[[[SSKProtoAttachmentPointer builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoAttachmentPointerBuilder*) builder {
  return [[SSKProtoAttachmentPointerBuilder alloc] init];
}
+ (SSKProtoAttachmentPointerBuilder*) builderWithPrototype:(SSKProtoAttachmentPointer*) prototype {
  return [[SSKProtoAttachmentPointer builder] mergeFrom:prototype];
}
- (SSKProtoAttachmentPointerBuilder*) builder {
  return [SSKProtoAttachmentPointer builder];
}
- (SSKProtoAttachmentPointerBuilder*) toBuilder {
  return [SSKProtoAttachmentPointer builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", [NSNumber numberWithLongLong:self.id]];
  }
  if (self.hasContentType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"contentType", self.contentType];
  }
  if (self.hasKey) {
    [output appendFormat:@"%@%@: %@\n", indent, @"key", self.key];
  }
  if (self.hasSize) {
    [output appendFormat:@"%@%@: %@\n", indent, @"size", [NSNumber numberWithInteger:self.size]];
  }
  if (self.hasThumbnail) {
    [output appendFormat:@"%@%@: %@\n", indent, @"thumbnail", self.thumbnail];
  }
  if (self.hasDigest) {
    [output appendFormat:@"%@%@: %@\n", indent, @"digest", self.digest];
  }
  if (self.hasFileName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"fileName", self.fileName];
  }
  if (self.hasFlags) {
    [output appendFormat:@"%@%@: %@\n", indent, @"flags", [NSNumber numberWithInteger:self.flags]];
  }
  if (self.hasWidth) {
    [output appendFormat:@"%@%@: %@\n", indent, @"width", [NSNumber numberWithInteger:self.width]];
  }
  if (self.hasHeight) {
    [output appendFormat:@"%@%@: %@\n", indent, @"height", [NSNumber numberWithInteger:self.height]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: [NSNumber numberWithLongLong:self.id] forKey: @"id"];
  }
  if (self.hasContentType) {
    [dictionary setObject: self.contentType forKey: @"contentType"];
  }
  if (self.hasKey) {
    [dictionary setObject: self.key forKey: @"key"];
  }
  if (self.hasSize) {
    [dictionary setObject: [NSNumber numberWithInteger:self.size] forKey: @"size"];
  }
  if (self.hasThumbnail) {
    [dictionary setObject: self.thumbnail forKey: @"thumbnail"];
  }
  if (self.hasDigest) {
    [dictionary setObject: self.digest forKey: @"digest"];
  }
  if (self.hasFileName) {
    [dictionary setObject: self.fileName forKey: @"fileName"];
  }
  if (self.hasFlags) {
    [dictionary setObject: [NSNumber numberWithInteger:self.flags] forKey: @"flags"];
  }
  if (self.hasWidth) {
    [dictionary setObject: [NSNumber numberWithInteger:self.width] forKey: @"width"];
  }
  if (self.hasHeight) {
    [dictionary setObject: [NSNumber numberWithInteger:self.height] forKey: @"height"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoAttachmentPointer class]]) {
    return NO;
  }
  SSKProtoAttachmentPointer *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || self.id == otherMessage.id) &&
      self.hasContentType == otherMessage.hasContentType &&
      (!self.hasContentType || [self.contentType isEqual:otherMessage.contentType]) &&
      self.hasKey == otherMessage.hasKey &&
      (!self.hasKey || [self.key isEqual:otherMessage.key]) &&
      self.hasSize == otherMessage.hasSize &&
      (!self.hasSize || self.size == otherMessage.size) &&
      self.hasThumbnail == otherMessage.hasThumbnail &&
      (!self.hasThumbnail || [self.thumbnail isEqual:otherMessage.thumbnail]) &&
      self.hasDigest == otherMessage.hasDigest &&
      (!self.hasDigest || [self.digest isEqual:otherMessage.digest]) &&
      self.hasFileName == otherMessage.hasFileName &&
      (!self.hasFileName || [self.fileName isEqual:otherMessage.fileName]) &&
      self.hasFlags == otherMessage.hasFlags &&
      (!self.hasFlags || self.flags == otherMessage.flags) &&
      self.hasWidth == otherMessage.hasWidth &&
      (!self.hasWidth || self.width == otherMessage.width) &&
      self.hasHeight == otherMessage.hasHeight &&
      (!self.hasHeight || self.height == otherMessage.height) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [[NSNumber numberWithLongLong:self.id] hash];
  }
  if (self.hasContentType) {
    hashCode = hashCode * 31 + [self.contentType hash];
  }
  if (self.hasKey) {
    hashCode = hashCode * 31 + [self.key hash];
  }
  if (self.hasSize) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.size] hash];
  }
  if (self.hasThumbnail) {
    hashCode = hashCode * 31 + [self.thumbnail hash];
  }
  if (self.hasDigest) {
    hashCode = hashCode * 31 + [self.digest hash];
  }
  if (self.hasFileName) {
    hashCode = hashCode * 31 + [self.fileName hash];
  }
  if (self.hasFlags) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.flags] hash];
  }
  if (self.hasWidth) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.width] hash];
  }
  if (self.hasHeight) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.height] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoAttachmentPointerFlagsIsValidValue(SSKProtoAttachmentPointerFlags value) {
  switch (value) {
    case SSKProtoAttachmentPointerFlagsVoiceMessage:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoAttachmentPointerFlags(SSKProtoAttachmentPointerFlags value) {
  switch (value) {
    case SSKProtoAttachmentPointerFlagsVoiceMessage:
      return @"SSKProtoAttachmentPointerFlagsVoiceMessage";
    default:
      return nil;
  }
}

@interface SSKProtoAttachmentPointerBuilder()
@property (strong) SSKProtoAttachmentPointer* resultAttachmentPointer;
@end

@implementation SSKProtoAttachmentPointerBuilder
@synthesize resultAttachmentPointer;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultAttachmentPointer = [[SSKProtoAttachmentPointer alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultAttachmentPointer;
}
- (SSKProtoAttachmentPointerBuilder*) clear {
  self.resultAttachmentPointer = [[SSKProtoAttachmentPointer alloc] init];
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clone {
  return [SSKProtoAttachmentPointer builderWithPrototype:resultAttachmentPointer];
}
- (SSKProtoAttachmentPointer*) defaultInstance {
  return [SSKProtoAttachmentPointer defaultInstance];
}
- (SSKProtoAttachmentPointer*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoAttachmentPointer*) buildPartial {
  SSKProtoAttachmentPointer* returnMe = resultAttachmentPointer;
  self.resultAttachmentPointer = nil;
  return returnMe;
}
- (SSKProtoAttachmentPointerBuilder*) mergeFrom:(SSKProtoAttachmentPointer*) other {
  if (other == [SSKProtoAttachmentPointer defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasContentType) {
    [self setContentType:other.contentType];
  }
  if (other.hasKey) {
    [self setKey:other.key];
  }
  if (other.hasSize) {
    [self setSize:other.size];
  }
  if (other.hasThumbnail) {
    [self setThumbnail:other.thumbnail];
  }
  if (other.hasDigest) {
    [self setDigest:other.digest];
  }
  if (other.hasFileName) {
    [self setFileName:other.fileName];
  }
  if (other.hasFlags) {
    [self setFlags:other.flags];
  }
  if (other.hasWidth) {
    [self setWidth:other.width];
  }
  if (other.hasHeight) {
    [self setHeight:other.height];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoAttachmentPointerBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 9: {
        [self setId:[input readFixed64]];
        break;
      }
      case 18: {
        [self setContentType:[input readString]];
        break;
      }
      case 26: {
        [self setKey:[input readData]];
        break;
      }
      case 32: {
        [self setSize:[input readUInt32]];
        break;
      }
      case 42: {
        [self setThumbnail:[input readData]];
        break;
      }
      case 50: {
        [self setDigest:[input readData]];
        break;
      }
      case 58: {
        [self setFileName:[input readString]];
        break;
      }
      case 64: {
        [self setFlags:[input readUInt32]];
        break;
      }
      case 72: {
        [self setWidth:[input readUInt32]];
        break;
      }
      case 80: {
        [self setHeight:[input readUInt32]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultAttachmentPointer.hasId;
}
- (UInt64) id {
  return resultAttachmentPointer.id;
}
- (SSKProtoAttachmentPointerBuilder*) setId:(UInt64) value {
  resultAttachmentPointer.hasId = YES;
  resultAttachmentPointer.id = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearId {
  resultAttachmentPointer.hasId = NO;
  resultAttachmentPointer.id = 0L;
  return self;
}
- (BOOL) hasContentType {
  return resultAttachmentPointer.hasContentType;
}
- (NSString*) contentType {
  return resultAttachmentPointer.contentType;
}
- (SSKProtoAttachmentPointerBuilder*) setContentType:(NSString*) value {
  resultAttachmentPointer.hasContentType = YES;
  resultAttachmentPointer.contentType = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearContentType {
  resultAttachmentPointer.hasContentType = NO;
  resultAttachmentPointer.contentType = @"";
  return self;
}
- (BOOL) hasKey {
  return resultAttachmentPointer.hasKey;
}
- (NSData*) key {
  return resultAttachmentPointer.key;
}
- (SSKProtoAttachmentPointerBuilder*) setKey:(NSData*) value {
  resultAttachmentPointer.hasKey = YES;
  resultAttachmentPointer.key = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearKey {
  resultAttachmentPointer.hasKey = NO;
  resultAttachmentPointer.key = [NSData data];
  return self;
}
- (BOOL) hasSize {
  return resultAttachmentPointer.hasSize;
}
- (UInt32) size {
  return resultAttachmentPointer.size;
}
- (SSKProtoAttachmentPointerBuilder*) setSize:(UInt32) value {
  resultAttachmentPointer.hasSize = YES;
  resultAttachmentPointer.size = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearSize {
  resultAttachmentPointer.hasSize = NO;
  resultAttachmentPointer.size = 0;
  return self;
}
- (BOOL) hasThumbnail {
  return resultAttachmentPointer.hasThumbnail;
}
- (NSData*) thumbnail {
  return resultAttachmentPointer.thumbnail;
}
- (SSKProtoAttachmentPointerBuilder*) setThumbnail:(NSData*) value {
  resultAttachmentPointer.hasThumbnail = YES;
  resultAttachmentPointer.thumbnail = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearThumbnail {
  resultAttachmentPointer.hasThumbnail = NO;
  resultAttachmentPointer.thumbnail = [NSData data];
  return self;
}
- (BOOL) hasDigest {
  return resultAttachmentPointer.hasDigest;
}
- (NSData*) digest {
  return resultAttachmentPointer.digest;
}
- (SSKProtoAttachmentPointerBuilder*) setDigest:(NSData*) value {
  resultAttachmentPointer.hasDigest = YES;
  resultAttachmentPointer.digest = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearDigest {
  resultAttachmentPointer.hasDigest = NO;
  resultAttachmentPointer.digest = [NSData data];
  return self;
}
- (BOOL) hasFileName {
  return resultAttachmentPointer.hasFileName;
}
- (NSString*) fileName {
  return resultAttachmentPointer.fileName;
}
- (SSKProtoAttachmentPointerBuilder*) setFileName:(NSString*) value {
  resultAttachmentPointer.hasFileName = YES;
  resultAttachmentPointer.fileName = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearFileName {
  resultAttachmentPointer.hasFileName = NO;
  resultAttachmentPointer.fileName = @"";
  return self;
}
- (BOOL) hasFlags {
  return resultAttachmentPointer.hasFlags;
}
- (UInt32) flags {
  return resultAttachmentPointer.flags;
}
- (SSKProtoAttachmentPointerBuilder*) setFlags:(UInt32) value {
  resultAttachmentPointer.hasFlags = YES;
  resultAttachmentPointer.flags = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearFlags {
  resultAttachmentPointer.hasFlags = NO;
  resultAttachmentPointer.flags = 0;
  return self;
}
- (BOOL) hasWidth {
  return resultAttachmentPointer.hasWidth;
}
- (UInt32) width {
  return resultAttachmentPointer.width;
}
- (SSKProtoAttachmentPointerBuilder*) setWidth:(UInt32) value {
  resultAttachmentPointer.hasWidth = YES;
  resultAttachmentPointer.width = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearWidth {
  resultAttachmentPointer.hasWidth = NO;
  resultAttachmentPointer.width = 0;
  return self;
}
- (BOOL) hasHeight {
  return resultAttachmentPointer.hasHeight;
}
- (UInt32) height {
  return resultAttachmentPointer.height;
}
- (SSKProtoAttachmentPointerBuilder*) setHeight:(UInt32) value {
  resultAttachmentPointer.hasHeight = YES;
  resultAttachmentPointer.height = value;
  return self;
}
- (SSKProtoAttachmentPointerBuilder*) clearHeight {
  resultAttachmentPointer.hasHeight = NO;
  resultAttachmentPointer.height = 0;
  return self;
}
@end

@interface SSKProtoGroupContext ()
@property (strong) NSData* id;
@property SSKProtoGroupContextType type;
@property (strong) NSString* name;
@property (strong) NSMutableArray * membersArray;
@property (strong) SSKProtoAttachmentPointer* avatar;
@end

@implementation SSKProtoGroupContext

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasType {
  return !!hasType_;
}
- (void) setHasType:(BOOL) _value_ {
  hasType_ = !!_value_;
}
@synthesize type;
- (BOOL) hasName {
  return !!hasName_;
}
- (void) setHasName:(BOOL) _value_ {
  hasName_ = !!_value_;
}
@synthesize name;
@synthesize membersArray;
@dynamic members;
- (BOOL) hasAvatar {
  return !!hasAvatar_;
}
- (void) setHasAvatar:(BOOL) _value_ {
  hasAvatar_ = !!_value_;
}
@synthesize avatar;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = [NSData data];
    self.type = SSKProtoGroupContextTypeUnknown;
    self.name = @"";
    self.avatar = [SSKProtoAttachmentPointer defaultInstance];
  }
  return self;
}
static SSKProtoGroupContext* defaultSSKProtoGroupContextInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoGroupContext class]) {
    defaultSSKProtoGroupContextInstance = [[SSKProtoGroupContext alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoGroupContextInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoGroupContextInstance;
}
- (NSArray *)members {
  return membersArray;
}
- (NSString*)membersAtIndex:(NSUInteger)index {
  return [membersArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeData:1 value:self.id];
  }
  if (self.hasType) {
    [output writeEnum:2 value:self.type];
  }
  if (self.hasName) {
    [output writeString:3 value:self.name];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    [output writeString:4 value:element];
  }];
  if (self.hasAvatar) {
    [output writeMessage:5 value:self.avatar];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeDataSize(1, self.id);
  }
  if (self.hasType) {
    size_ += computeEnumSize(2, self.type);
  }
  if (self.hasName) {
    size_ += computeStringSize(3, self.name);
  }
  {
    __block SInt32 dataSize = 0;
    const NSUInteger count = self.membersArray.count;
    [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
      dataSize += computeStringSizeNoTag(element);
    }];
    size_ += dataSize;
    size_ += (SInt32)(1 * count);
  }
  if (self.hasAvatar) {
    size_ += computeMessageSize(5, self.avatar);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoGroupContext*) parseFromData:(NSData*) data {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromData:data] build];
}
+ (SSKProtoGroupContext*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupContext*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromInputStream:input] build];
}
+ (SSKProtoGroupContext*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupContext*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoGroupContext*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupContext*)[[[SSKProtoGroupContext builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupContextBuilder*) builder {
  return [[SSKProtoGroupContextBuilder alloc] init];
}
+ (SSKProtoGroupContextBuilder*) builderWithPrototype:(SSKProtoGroupContext*) prototype {
  return [[SSKProtoGroupContext builder] mergeFrom:prototype];
}
- (SSKProtoGroupContextBuilder*) builder {
  return [SSKProtoGroupContext builder];
}
- (SSKProtoGroupContextBuilder*) toBuilder {
  return [SSKProtoGroupContext builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", self.id];
  }
  if (self.hasType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"type", NSStringFromSSKProtoGroupContextType(self.type)];
  }
  if (self.hasName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"name", self.name];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@: %@\n", indent, @"members", obj];
  }];
  if (self.hasAvatar) {
    [output appendFormat:@"%@%@ {\n", indent, @"avatar"];
    [self.avatar writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: self.id forKey: @"id"];
  }
  if (self.hasType) {
    [dictionary setObject: @(self.type) forKey: @"type"];
  }
  if (self.hasName) {
    [dictionary setObject: self.name forKey: @"name"];
  }
  [dictionary setObject:self.members forKey: @"members"];
  if (self.hasAvatar) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.avatar storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"avatar"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoGroupContext class]]) {
    return NO;
  }
  SSKProtoGroupContext *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || [self.id isEqual:otherMessage.id]) &&
      self.hasType == otherMessage.hasType &&
      (!self.hasType || self.type == otherMessage.type) &&
      self.hasName == otherMessage.hasName &&
      (!self.hasName || [self.name isEqual:otherMessage.name]) &&
      [self.membersArray isEqualToArray:otherMessage.membersArray] &&
      self.hasAvatar == otherMessage.hasAvatar &&
      (!self.hasAvatar || [self.avatar isEqual:otherMessage.avatar]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [self.id hash];
  }
  if (self.hasType) {
    hashCode = hashCode * 31 + self.type;
  }
  if (self.hasName) {
    hashCode = hashCode * 31 + [self.name hash];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasAvatar) {
    hashCode = hashCode * 31 + [self.avatar hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

BOOL SSKProtoGroupContextTypeIsValidValue(SSKProtoGroupContextType value) {
  switch (value) {
    case SSKProtoGroupContextTypeUnknown:
    case SSKProtoGroupContextTypeUpdate:
    case SSKProtoGroupContextTypeDeliver:
    case SSKProtoGroupContextTypeQuit:
    case SSKProtoGroupContextTypeRequestInfo:
      return YES;
    default:
      return NO;
  }
}
NSString *NSStringFromSSKProtoGroupContextType(SSKProtoGroupContextType value) {
  switch (value) {
    case SSKProtoGroupContextTypeUnknown:
      return @"SSKProtoGroupContextTypeUnknown";
    case SSKProtoGroupContextTypeUpdate:
      return @"SSKProtoGroupContextTypeUpdate";
    case SSKProtoGroupContextTypeDeliver:
      return @"SSKProtoGroupContextTypeDeliver";
    case SSKProtoGroupContextTypeQuit:
      return @"SSKProtoGroupContextTypeQuit";
    case SSKProtoGroupContextTypeRequestInfo:
      return @"SSKProtoGroupContextTypeRequestInfo";
    default:
      return nil;
  }
}

@interface SSKProtoGroupContextBuilder()
@property (strong) SSKProtoGroupContext* resultGroupContext;
@end

@implementation SSKProtoGroupContextBuilder
@synthesize resultGroupContext;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultGroupContext = [[SSKProtoGroupContext alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultGroupContext;
}
- (SSKProtoGroupContextBuilder*) clear {
  self.resultGroupContext = [[SSKProtoGroupContext alloc] init];
  return self;
}
- (SSKProtoGroupContextBuilder*) clone {
  return [SSKProtoGroupContext builderWithPrototype:resultGroupContext];
}
- (SSKProtoGroupContext*) defaultInstance {
  return [SSKProtoGroupContext defaultInstance];
}
- (SSKProtoGroupContext*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoGroupContext*) buildPartial {
  SSKProtoGroupContext* returnMe = resultGroupContext;
  self.resultGroupContext = nil;
  return returnMe;
}
- (SSKProtoGroupContextBuilder*) mergeFrom:(SSKProtoGroupContext*) other {
  if (other == [SSKProtoGroupContext defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasType) {
    [self setType:other.type];
  }
  if (other.hasName) {
    [self setName:other.name];
  }
  if (other.membersArray.count > 0) {
    if (resultGroupContext.membersArray == nil) {
      resultGroupContext.membersArray = [[NSMutableArray alloc] initWithArray:other.membersArray];
    } else {
      [resultGroupContext.membersArray addObjectsFromArray:other.membersArray];
    }
  }
  if (other.hasAvatar) {
    [self mergeAvatar:other.avatar];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoGroupContextBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoGroupContextBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setId:[input readData]];
        break;
      }
      case 16: {
        SSKProtoGroupContextType value = (SSKProtoGroupContextType)[input readEnum];
        if (SSKProtoGroupContextTypeIsValidValue(value)) {
          [self setType:value];
        } else {
          [unknownFields mergeVarintField:2 value:value];
        }
        break;
      }
      case 26: {
        [self setName:[input readString]];
        break;
      }
      case 34: {
        [self addMembers:[input readString]];
        break;
      }
      case 42: {
        SSKProtoAttachmentPointerBuilder* subBuilder = [SSKProtoAttachmentPointer builder];
        if (self.hasAvatar) {
          [subBuilder mergeFrom:self.avatar];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAvatar:[subBuilder buildPartial]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultGroupContext.hasId;
}
- (NSData*) id {
  return resultGroupContext.id;
}
- (SSKProtoGroupContextBuilder*) setId:(NSData*) value {
  resultGroupContext.hasId = YES;
  resultGroupContext.id = value;
  return self;
}
- (SSKProtoGroupContextBuilder*) clearId {
  resultGroupContext.hasId = NO;
  resultGroupContext.id = [NSData data];
  return self;
}
- (BOOL) hasType {
  return resultGroupContext.hasType;
}
- (SSKProtoGroupContextType) type {
  return resultGroupContext.type;
}
- (SSKProtoGroupContextBuilder*) setType:(SSKProtoGroupContextType) value {
  resultGroupContext.hasType = YES;
  resultGroupContext.type = value;
  return self;
}
- (SSKProtoGroupContextBuilder*) clearType {
  resultGroupContext.hasType = NO;
  resultGroupContext.type = SSKProtoGroupContextTypeUnknown;
  return self;
}
- (BOOL) hasName {
  return resultGroupContext.hasName;
}
- (NSString*) name {
  return resultGroupContext.name;
}
- (SSKProtoGroupContextBuilder*) setName:(NSString*) value {
  resultGroupContext.hasName = YES;
  resultGroupContext.name = value;
  return self;
}
- (SSKProtoGroupContextBuilder*) clearName {
  resultGroupContext.hasName = NO;
  resultGroupContext.name = @"";
  return self;
}
- (NSMutableArray *)members {
  return resultGroupContext.membersArray;
}
- (NSString*)membersAtIndex:(NSUInteger)index {
  return [resultGroupContext membersAtIndex:index];
}
- (SSKProtoGroupContextBuilder *)addMembers:(NSString*)value {
  if (resultGroupContext.membersArray == nil) {
    resultGroupContext.membersArray = [[NSMutableArray alloc]init];
  }
  [resultGroupContext.membersArray addObject:value];
  return self;
}
- (SSKProtoGroupContextBuilder *)setMembersArray:(NSArray *)array {
  resultGroupContext.membersArray = [[NSMutableArray alloc] initWithArray:array];
  return self;
}
- (SSKProtoGroupContextBuilder *)clearMembers {
  resultGroupContext.membersArray = nil;
  return self;
}
- (BOOL) hasAvatar {
  return resultGroupContext.hasAvatar;
}
- (SSKProtoAttachmentPointer*) avatar {
  return resultGroupContext.avatar;
}
- (SSKProtoGroupContextBuilder*) setAvatar:(SSKProtoAttachmentPointer*) value {
  resultGroupContext.hasAvatar = YES;
  resultGroupContext.avatar = value;
  return self;
}
- (SSKProtoGroupContextBuilder*) setAvatarBuilder:(SSKProtoAttachmentPointerBuilder*) builderForValue {
  return [self setAvatar:[builderForValue build]];
}
- (SSKProtoGroupContextBuilder*) mergeAvatar:(SSKProtoAttachmentPointer*) value {
  if (resultGroupContext.hasAvatar &&
      resultGroupContext.avatar != [SSKProtoAttachmentPointer defaultInstance]) {
    resultGroupContext.avatar =
      [[[SSKProtoAttachmentPointer builderWithPrototype:resultGroupContext.avatar] mergeFrom:value] buildPartial];
  } else {
    resultGroupContext.avatar = value;
  }
  resultGroupContext.hasAvatar = YES;
  return self;
}
- (SSKProtoGroupContextBuilder*) clearAvatar {
  resultGroupContext.hasAvatar = NO;
  resultGroupContext.avatar = [SSKProtoAttachmentPointer defaultInstance];
  return self;
}
@end

@interface SSKProtoContactDetails ()
@property (strong) NSString* number;
@property (strong) NSString* name;
@property (strong) SSKProtoContactDetailsAvatar* avatar;
@property (strong) NSString* color;
@property (strong) SSKProtoVerified* verified;
@property (strong) NSData* profileKey;
@property BOOL blocked;
@property UInt32 expireTimer;
@end

@implementation SSKProtoContactDetails

- (BOOL) hasNumber {
  return !!hasNumber_;
}
- (void) setHasNumber:(BOOL) _value_ {
  hasNumber_ = !!_value_;
}
@synthesize number;
- (BOOL) hasName {
  return !!hasName_;
}
- (void) setHasName:(BOOL) _value_ {
  hasName_ = !!_value_;
}
@synthesize name;
- (BOOL) hasAvatar {
  return !!hasAvatar_;
}
- (void) setHasAvatar:(BOOL) _value_ {
  hasAvatar_ = !!_value_;
}
@synthesize avatar;
- (BOOL) hasColor {
  return !!hasColor_;
}
- (void) setHasColor:(BOOL) _value_ {
  hasColor_ = !!_value_;
}
@synthesize color;
- (BOOL) hasVerified {
  return !!hasVerified_;
}
- (void) setHasVerified:(BOOL) _value_ {
  hasVerified_ = !!_value_;
}
@synthesize verified;
- (BOOL) hasProfileKey {
  return !!hasProfileKey_;
}
- (void) setHasProfileKey:(BOOL) _value_ {
  hasProfileKey_ = !!_value_;
}
@synthesize profileKey;
- (BOOL) hasBlocked {
  return !!hasBlocked_;
}
- (void) setHasBlocked:(BOOL) _value_ {
  hasBlocked_ = !!_value_;
}
- (BOOL) blocked {
  return !!blocked_;
}
- (void) setBlocked:(BOOL) _value_ {
  blocked_ = !!_value_;
}
- (BOOL) hasExpireTimer {
  return !!hasExpireTimer_;
}
- (void) setHasExpireTimer:(BOOL) _value_ {
  hasExpireTimer_ = !!_value_;
}
@synthesize expireTimer;
- (instancetype) init {
  if ((self = [super init])) {
    self.number = @"";
    self.name = @"";
    self.avatar = [SSKProtoContactDetailsAvatar defaultInstance];
    self.color = @"";
    self.verified = [SSKProtoVerified defaultInstance];
    self.profileKey = [NSData data];
    self.blocked = NO;
    self.expireTimer = 0;
  }
  return self;
}
static SSKProtoContactDetails* defaultSSKProtoContactDetailsInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoContactDetails class]) {
    defaultSSKProtoContactDetailsInstance = [[SSKProtoContactDetails alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoContactDetailsInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoContactDetailsInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasNumber) {
    [output writeString:1 value:self.number];
  }
  if (self.hasName) {
    [output writeString:2 value:self.name];
  }
  if (self.hasAvatar) {
    [output writeMessage:3 value:self.avatar];
  }
  if (self.hasColor) {
    [output writeString:4 value:self.color];
  }
  if (self.hasVerified) {
    [output writeMessage:5 value:self.verified];
  }
  if (self.hasProfileKey) {
    [output writeData:6 value:self.profileKey];
  }
  if (self.hasBlocked) {
    [output writeBool:7 value:self.blocked];
  }
  if (self.hasExpireTimer) {
    [output writeUInt32:8 value:self.expireTimer];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasNumber) {
    size_ += computeStringSize(1, self.number);
  }
  if (self.hasName) {
    size_ += computeStringSize(2, self.name);
  }
  if (self.hasAvatar) {
    size_ += computeMessageSize(3, self.avatar);
  }
  if (self.hasColor) {
    size_ += computeStringSize(4, self.color);
  }
  if (self.hasVerified) {
    size_ += computeMessageSize(5, self.verified);
  }
  if (self.hasProfileKey) {
    size_ += computeDataSize(6, self.profileKey);
  }
  if (self.hasBlocked) {
    size_ += computeBoolSize(7, self.blocked);
  }
  if (self.hasExpireTimer) {
    size_ += computeUInt32Size(8, self.expireTimer);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoContactDetails*) parseFromData:(NSData*) data {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromData:data] build];
}
+ (SSKProtoContactDetails*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetails*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromInputStream:input] build];
}
+ (SSKProtoContactDetails*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoContactDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetails*)[[[SSKProtoContactDetails builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetailsBuilder*) builder {
  return [[SSKProtoContactDetailsBuilder alloc] init];
}
+ (SSKProtoContactDetailsBuilder*) builderWithPrototype:(SSKProtoContactDetails*) prototype {
  return [[SSKProtoContactDetails builder] mergeFrom:prototype];
}
- (SSKProtoContactDetailsBuilder*) builder {
  return [SSKProtoContactDetails builder];
}
- (SSKProtoContactDetailsBuilder*) toBuilder {
  return [SSKProtoContactDetails builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasNumber) {
    [output appendFormat:@"%@%@: %@\n", indent, @"number", self.number];
  }
  if (self.hasName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"name", self.name];
  }
  if (self.hasAvatar) {
    [output appendFormat:@"%@%@ {\n", indent, @"avatar"];
    [self.avatar writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasColor) {
    [output appendFormat:@"%@%@: %@\n", indent, @"color", self.color];
  }
  if (self.hasVerified) {
    [output appendFormat:@"%@%@ {\n", indent, @"verified"];
    [self.verified writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasProfileKey) {
    [output appendFormat:@"%@%@: %@\n", indent, @"profileKey", self.profileKey];
  }
  if (self.hasBlocked) {
    [output appendFormat:@"%@%@: %@\n", indent, @"blocked", [NSNumber numberWithBool:self.blocked]];
  }
  if (self.hasExpireTimer) {
    [output appendFormat:@"%@%@: %@\n", indent, @"expireTimer", [NSNumber numberWithInteger:self.expireTimer]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasNumber) {
    [dictionary setObject: self.number forKey: @"number"];
  }
  if (self.hasName) {
    [dictionary setObject: self.name forKey: @"name"];
  }
  if (self.hasAvatar) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.avatar storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"avatar"];
  }
  if (self.hasColor) {
    [dictionary setObject: self.color forKey: @"color"];
  }
  if (self.hasVerified) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.verified storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"verified"];
  }
  if (self.hasProfileKey) {
    [dictionary setObject: self.profileKey forKey: @"profileKey"];
  }
  if (self.hasBlocked) {
    [dictionary setObject: [NSNumber numberWithBool:self.blocked] forKey: @"blocked"];
  }
  if (self.hasExpireTimer) {
    [dictionary setObject: [NSNumber numberWithInteger:self.expireTimer] forKey: @"expireTimer"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoContactDetails class]]) {
    return NO;
  }
  SSKProtoContactDetails *otherMessage = other;
  return
      self.hasNumber == otherMessage.hasNumber &&
      (!self.hasNumber || [self.number isEqual:otherMessage.number]) &&
      self.hasName == otherMessage.hasName &&
      (!self.hasName || [self.name isEqual:otherMessage.name]) &&
      self.hasAvatar == otherMessage.hasAvatar &&
      (!self.hasAvatar || [self.avatar isEqual:otherMessage.avatar]) &&
      self.hasColor == otherMessage.hasColor &&
      (!self.hasColor || [self.color isEqual:otherMessage.color]) &&
      self.hasVerified == otherMessage.hasVerified &&
      (!self.hasVerified || [self.verified isEqual:otherMessage.verified]) &&
      self.hasProfileKey == otherMessage.hasProfileKey &&
      (!self.hasProfileKey || [self.profileKey isEqual:otherMessage.profileKey]) &&
      self.hasBlocked == otherMessage.hasBlocked &&
      (!self.hasBlocked || self.blocked == otherMessage.blocked) &&
      self.hasExpireTimer == otherMessage.hasExpireTimer &&
      (!self.hasExpireTimer || self.expireTimer == otherMessage.expireTimer) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasNumber) {
    hashCode = hashCode * 31 + [self.number hash];
  }
  if (self.hasName) {
    hashCode = hashCode * 31 + [self.name hash];
  }
  if (self.hasAvatar) {
    hashCode = hashCode * 31 + [self.avatar hash];
  }
  if (self.hasColor) {
    hashCode = hashCode * 31 + [self.color hash];
  }
  if (self.hasVerified) {
    hashCode = hashCode * 31 + [self.verified hash];
  }
  if (self.hasProfileKey) {
    hashCode = hashCode * 31 + [self.profileKey hash];
  }
  if (self.hasBlocked) {
    hashCode = hashCode * 31 + [[NSNumber numberWithBool:self.blocked] hash];
  }
  if (self.hasExpireTimer) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.expireTimer] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoContactDetailsAvatar ()
@property (strong) NSString* contentType;
@property UInt32 length;
@end

@implementation SSKProtoContactDetailsAvatar

- (BOOL) hasContentType {
  return !!hasContentType_;
}
- (void) setHasContentType:(BOOL) _value_ {
  hasContentType_ = !!_value_;
}
@synthesize contentType;
- (BOOL) hasLength {
  return !!hasLength_;
}
- (void) setHasLength:(BOOL) _value_ {
  hasLength_ = !!_value_;
}
@synthesize length;
- (instancetype) init {
  if ((self = [super init])) {
    self.contentType = @"";
    self.length = 0;
  }
  return self;
}
static SSKProtoContactDetailsAvatar* defaultSSKProtoContactDetailsAvatarInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoContactDetailsAvatar class]) {
    defaultSSKProtoContactDetailsAvatarInstance = [[SSKProtoContactDetailsAvatar alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoContactDetailsAvatarInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoContactDetailsAvatarInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasContentType) {
    [output writeString:1 value:self.contentType];
  }
  if (self.hasLength) {
    [output writeUInt32:2 value:self.length];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasContentType) {
    size_ += computeStringSize(1, self.contentType);
  }
  if (self.hasLength) {
    size_ += computeUInt32Size(2, self.length);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoContactDetailsAvatar*) parseFromData:(NSData*) data {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromData:data] build];
}
+ (SSKProtoContactDetailsAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetailsAvatar*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromInputStream:input] build];
}
+ (SSKProtoContactDetailsAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoContactDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoContactDetailsAvatar*)[[[SSKProtoContactDetailsAvatar builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoContactDetailsAvatarBuilder*) builder {
  return [[SSKProtoContactDetailsAvatarBuilder alloc] init];
}
+ (SSKProtoContactDetailsAvatarBuilder*) builderWithPrototype:(SSKProtoContactDetailsAvatar*) prototype {
  return [[SSKProtoContactDetailsAvatar builder] mergeFrom:prototype];
}
- (SSKProtoContactDetailsAvatarBuilder*) builder {
  return [SSKProtoContactDetailsAvatar builder];
}
- (SSKProtoContactDetailsAvatarBuilder*) toBuilder {
  return [SSKProtoContactDetailsAvatar builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasContentType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"contentType", self.contentType];
  }
  if (self.hasLength) {
    [output appendFormat:@"%@%@: %@\n", indent, @"length", [NSNumber numberWithInteger:self.length]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasContentType) {
    [dictionary setObject: self.contentType forKey: @"contentType"];
  }
  if (self.hasLength) {
    [dictionary setObject: [NSNumber numberWithInteger:self.length] forKey: @"length"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoContactDetailsAvatar class]]) {
    return NO;
  }
  SSKProtoContactDetailsAvatar *otherMessage = other;
  return
      self.hasContentType == otherMessage.hasContentType &&
      (!self.hasContentType || [self.contentType isEqual:otherMessage.contentType]) &&
      self.hasLength == otherMessage.hasLength &&
      (!self.hasLength || self.length == otherMessage.length) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasContentType) {
    hashCode = hashCode * 31 + [self.contentType hash];
  }
  if (self.hasLength) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.length] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoContactDetailsAvatarBuilder()
@property (strong) SSKProtoContactDetailsAvatar* resultAvatar;
@end

@implementation SSKProtoContactDetailsAvatarBuilder
@synthesize resultAvatar;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultAvatar = [[SSKProtoContactDetailsAvatar alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultAvatar;
}
- (SSKProtoContactDetailsAvatarBuilder*) clear {
  self.resultAvatar = [[SSKProtoContactDetailsAvatar alloc] init];
  return self;
}
- (SSKProtoContactDetailsAvatarBuilder*) clone {
  return [SSKProtoContactDetailsAvatar builderWithPrototype:resultAvatar];
}
- (SSKProtoContactDetailsAvatar*) defaultInstance {
  return [SSKProtoContactDetailsAvatar defaultInstance];
}
- (SSKProtoContactDetailsAvatar*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoContactDetailsAvatar*) buildPartial {
  SSKProtoContactDetailsAvatar* returnMe = resultAvatar;
  self.resultAvatar = nil;
  return returnMe;
}
- (SSKProtoContactDetailsAvatarBuilder*) mergeFrom:(SSKProtoContactDetailsAvatar*) other {
  if (other == [SSKProtoContactDetailsAvatar defaultInstance]) {
    return self;
  }
  if (other.hasContentType) {
    [self setContentType:other.contentType];
  }
  if (other.hasLength) {
    [self setLength:other.length];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoContactDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoContactDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setContentType:[input readString]];
        break;
      }
      case 16: {
        [self setLength:[input readUInt32]];
        break;
      }
    }
  }
}
- (BOOL) hasContentType {
  return resultAvatar.hasContentType;
}
- (NSString*) contentType {
  return resultAvatar.contentType;
}
- (SSKProtoContactDetailsAvatarBuilder*) setContentType:(NSString*) value {
  resultAvatar.hasContentType = YES;
  resultAvatar.contentType = value;
  return self;
}
- (SSKProtoContactDetailsAvatarBuilder*) clearContentType {
  resultAvatar.hasContentType = NO;
  resultAvatar.contentType = @"";
  return self;
}
- (BOOL) hasLength {
  return resultAvatar.hasLength;
}
- (UInt32) length {
  return resultAvatar.length;
}
- (SSKProtoContactDetailsAvatarBuilder*) setLength:(UInt32) value {
  resultAvatar.hasLength = YES;
  resultAvatar.length = value;
  return self;
}
- (SSKProtoContactDetailsAvatarBuilder*) clearLength {
  resultAvatar.hasLength = NO;
  resultAvatar.length = 0;
  return self;
}
@end

@interface SSKProtoContactDetailsBuilder()
@property (strong) SSKProtoContactDetails* resultContactDetails;
@end

@implementation SSKProtoContactDetailsBuilder
@synthesize resultContactDetails;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultContactDetails = [[SSKProtoContactDetails alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultContactDetails;
}
- (SSKProtoContactDetailsBuilder*) clear {
  self.resultContactDetails = [[SSKProtoContactDetails alloc] init];
  return self;
}
- (SSKProtoContactDetailsBuilder*) clone {
  return [SSKProtoContactDetails builderWithPrototype:resultContactDetails];
}
- (SSKProtoContactDetails*) defaultInstance {
  return [SSKProtoContactDetails defaultInstance];
}
- (SSKProtoContactDetails*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoContactDetails*) buildPartial {
  SSKProtoContactDetails* returnMe = resultContactDetails;
  self.resultContactDetails = nil;
  return returnMe;
}
- (SSKProtoContactDetailsBuilder*) mergeFrom:(SSKProtoContactDetails*) other {
  if (other == [SSKProtoContactDetails defaultInstance]) {
    return self;
  }
  if (other.hasNumber) {
    [self setNumber:other.number];
  }
  if (other.hasName) {
    [self setName:other.name];
  }
  if (other.hasAvatar) {
    [self mergeAvatar:other.avatar];
  }
  if (other.hasColor) {
    [self setColor:other.color];
  }
  if (other.hasVerified) {
    [self mergeVerified:other.verified];
  }
  if (other.hasProfileKey) {
    [self setProfileKey:other.profileKey];
  }
  if (other.hasBlocked) {
    [self setBlocked:other.blocked];
  }
  if (other.hasExpireTimer) {
    [self setExpireTimer:other.expireTimer];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoContactDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoContactDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setNumber:[input readString]];
        break;
      }
      case 18: {
        [self setName:[input readString]];
        break;
      }
      case 26: {
        SSKProtoContactDetailsAvatarBuilder* subBuilder = [SSKProtoContactDetailsAvatar builder];
        if (self.hasAvatar) {
          [subBuilder mergeFrom:self.avatar];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAvatar:[subBuilder buildPartial]];
        break;
      }
      case 34: {
        [self setColor:[input readString]];
        break;
      }
      case 42: {
        SSKProtoVerifiedBuilder* subBuilder = [SSKProtoVerified builder];
        if (self.hasVerified) {
          [subBuilder mergeFrom:self.verified];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setVerified:[subBuilder buildPartial]];
        break;
      }
      case 50: {
        [self setProfileKey:[input readData]];
        break;
      }
      case 56: {
        [self setBlocked:[input readBool]];
        break;
      }
      case 64: {
        [self setExpireTimer:[input readUInt32]];
        break;
      }
    }
  }
}
- (BOOL) hasNumber {
  return resultContactDetails.hasNumber;
}
- (NSString*) number {
  return resultContactDetails.number;
}
- (SSKProtoContactDetailsBuilder*) setNumber:(NSString*) value {
  resultContactDetails.hasNumber = YES;
  resultContactDetails.number = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearNumber {
  resultContactDetails.hasNumber = NO;
  resultContactDetails.number = @"";
  return self;
}
- (BOOL) hasName {
  return resultContactDetails.hasName;
}
- (NSString*) name {
  return resultContactDetails.name;
}
- (SSKProtoContactDetailsBuilder*) setName:(NSString*) value {
  resultContactDetails.hasName = YES;
  resultContactDetails.name = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearName {
  resultContactDetails.hasName = NO;
  resultContactDetails.name = @"";
  return self;
}
- (BOOL) hasAvatar {
  return resultContactDetails.hasAvatar;
}
- (SSKProtoContactDetailsAvatar*) avatar {
  return resultContactDetails.avatar;
}
- (SSKProtoContactDetailsBuilder*) setAvatar:(SSKProtoContactDetailsAvatar*) value {
  resultContactDetails.hasAvatar = YES;
  resultContactDetails.avatar = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) setAvatarBuilder:(SSKProtoContactDetailsAvatarBuilder*) builderForValue {
  return [self setAvatar:[builderForValue build]];
}
- (SSKProtoContactDetailsBuilder*) mergeAvatar:(SSKProtoContactDetailsAvatar*) value {
  if (resultContactDetails.hasAvatar &&
      resultContactDetails.avatar != [SSKProtoContactDetailsAvatar defaultInstance]) {
    resultContactDetails.avatar =
      [[[SSKProtoContactDetailsAvatar builderWithPrototype:resultContactDetails.avatar] mergeFrom:value] buildPartial];
  } else {
    resultContactDetails.avatar = value;
  }
  resultContactDetails.hasAvatar = YES;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearAvatar {
  resultContactDetails.hasAvatar = NO;
  resultContactDetails.avatar = [SSKProtoContactDetailsAvatar defaultInstance];
  return self;
}
- (BOOL) hasColor {
  return resultContactDetails.hasColor;
}
- (NSString*) color {
  return resultContactDetails.color;
}
- (SSKProtoContactDetailsBuilder*) setColor:(NSString*) value {
  resultContactDetails.hasColor = YES;
  resultContactDetails.color = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearColor {
  resultContactDetails.hasColor = NO;
  resultContactDetails.color = @"";
  return self;
}
- (BOOL) hasVerified {
  return resultContactDetails.hasVerified;
}
- (SSKProtoVerified*) verified {
  return resultContactDetails.verified;
}
- (SSKProtoContactDetailsBuilder*) setVerified:(SSKProtoVerified*) value {
  resultContactDetails.hasVerified = YES;
  resultContactDetails.verified = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) setVerifiedBuilder:(SSKProtoVerifiedBuilder*) builderForValue {
  return [self setVerified:[builderForValue build]];
}
- (SSKProtoContactDetailsBuilder*) mergeVerified:(SSKProtoVerified*) value {
  if (resultContactDetails.hasVerified &&
      resultContactDetails.verified != [SSKProtoVerified defaultInstance]) {
    resultContactDetails.verified =
      [[[SSKProtoVerified builderWithPrototype:resultContactDetails.verified] mergeFrom:value] buildPartial];
  } else {
    resultContactDetails.verified = value;
  }
  resultContactDetails.hasVerified = YES;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearVerified {
  resultContactDetails.hasVerified = NO;
  resultContactDetails.verified = [SSKProtoVerified defaultInstance];
  return self;
}
- (BOOL) hasProfileKey {
  return resultContactDetails.hasProfileKey;
}
- (NSData*) profileKey {
  return resultContactDetails.profileKey;
}
- (SSKProtoContactDetailsBuilder*) setProfileKey:(NSData*) value {
  resultContactDetails.hasProfileKey = YES;
  resultContactDetails.profileKey = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearProfileKey {
  resultContactDetails.hasProfileKey = NO;
  resultContactDetails.profileKey = [NSData data];
  return self;
}
- (BOOL) hasBlocked {
  return resultContactDetails.hasBlocked;
}
- (BOOL) blocked {
  return resultContactDetails.blocked;
}
- (SSKProtoContactDetailsBuilder*) setBlocked:(BOOL) value {
  resultContactDetails.hasBlocked = YES;
  resultContactDetails.blocked = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearBlocked {
  resultContactDetails.hasBlocked = NO;
  resultContactDetails.blocked = NO;
  return self;
}
- (BOOL) hasExpireTimer {
  return resultContactDetails.hasExpireTimer;
}
- (UInt32) expireTimer {
  return resultContactDetails.expireTimer;
}
- (SSKProtoContactDetailsBuilder*) setExpireTimer:(UInt32) value {
  resultContactDetails.hasExpireTimer = YES;
  resultContactDetails.expireTimer = value;
  return self;
}
- (SSKProtoContactDetailsBuilder*) clearExpireTimer {
  resultContactDetails.hasExpireTimer = NO;
  resultContactDetails.expireTimer = 0;
  return self;
}
@end

@interface SSKProtoGroupDetails ()
@property (strong) NSData* id;
@property (strong) NSString* name;
@property (strong) NSMutableArray * membersArray;
@property (strong) SSKProtoGroupDetailsAvatar* avatar;
@property BOOL active;
@property UInt32 expireTimer;
@property (strong) NSString* color;
@end

@implementation SSKProtoGroupDetails

- (BOOL) hasId {
  return !!hasId_;
}
- (void) setHasId:(BOOL) _value_ {
  hasId_ = !!_value_;
}
@synthesize id;
- (BOOL) hasName {
  return !!hasName_;
}
- (void) setHasName:(BOOL) _value_ {
  hasName_ = !!_value_;
}
@synthesize name;
@synthesize membersArray;
@dynamic members;
- (BOOL) hasAvatar {
  return !!hasAvatar_;
}
- (void) setHasAvatar:(BOOL) _value_ {
  hasAvatar_ = !!_value_;
}
@synthesize avatar;
- (BOOL) hasActive {
  return !!hasActive_;
}
- (void) setHasActive:(BOOL) _value_ {
  hasActive_ = !!_value_;
}
- (BOOL) active {
  return !!active_;
}
- (void) setActive:(BOOL) _value_ {
  active_ = !!_value_;
}
- (BOOL) hasExpireTimer {
  return !!hasExpireTimer_;
}
- (void) setHasExpireTimer:(BOOL) _value_ {
  hasExpireTimer_ = !!_value_;
}
@synthesize expireTimer;
- (BOOL) hasColor {
  return !!hasColor_;
}
- (void) setHasColor:(BOOL) _value_ {
  hasColor_ = !!_value_;
}
@synthesize color;
- (instancetype) init {
  if ((self = [super init])) {
    self.id = [NSData data];
    self.name = @"";
    self.avatar = [SSKProtoGroupDetailsAvatar defaultInstance];
    self.active = YES;
    self.expireTimer = 0;
    self.color = @"";
  }
  return self;
}
static SSKProtoGroupDetails* defaultSSKProtoGroupDetailsInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoGroupDetails class]) {
    defaultSSKProtoGroupDetailsInstance = [[SSKProtoGroupDetails alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoGroupDetailsInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoGroupDetailsInstance;
}
- (NSArray *)members {
  return membersArray;
}
- (NSString*)membersAtIndex:(NSUInteger)index {
  return [membersArray objectAtIndex:index];
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasId) {
    [output writeData:1 value:self.id];
  }
  if (self.hasName) {
    [output writeString:2 value:self.name];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    [output writeString:3 value:element];
  }];
  if (self.hasAvatar) {
    [output writeMessage:4 value:self.avatar];
  }
  if (self.hasActive) {
    [output writeBool:5 value:self.active];
  }
  if (self.hasExpireTimer) {
    [output writeUInt32:6 value:self.expireTimer];
  }
  if (self.hasColor) {
    [output writeString:7 value:self.color];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasId) {
    size_ += computeDataSize(1, self.id);
  }
  if (self.hasName) {
    size_ += computeStringSize(2, self.name);
  }
  {
    __block SInt32 dataSize = 0;
    const NSUInteger count = self.membersArray.count;
    [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
      dataSize += computeStringSizeNoTag(element);
    }];
    size_ += dataSize;
    size_ += (SInt32)(1 * count);
  }
  if (self.hasAvatar) {
    size_ += computeMessageSize(4, self.avatar);
  }
  if (self.hasActive) {
    size_ += computeBoolSize(5, self.active);
  }
  if (self.hasExpireTimer) {
    size_ += computeUInt32Size(6, self.expireTimer);
  }
  if (self.hasColor) {
    size_ += computeStringSize(7, self.color);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoGroupDetails*) parseFromData:(NSData*) data {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromData:data] build];
}
+ (SSKProtoGroupDetails*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetails*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromInputStream:input] build];
}
+ (SSKProtoGroupDetails*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoGroupDetails*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetails*)[[[SSKProtoGroupDetails builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetailsBuilder*) builder {
  return [[SSKProtoGroupDetailsBuilder alloc] init];
}
+ (SSKProtoGroupDetailsBuilder*) builderWithPrototype:(SSKProtoGroupDetails*) prototype {
  return [[SSKProtoGroupDetails builder] mergeFrom:prototype];
}
- (SSKProtoGroupDetailsBuilder*) builder {
  return [SSKProtoGroupDetails builder];
}
- (SSKProtoGroupDetailsBuilder*) toBuilder {
  return [SSKProtoGroupDetails builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasId) {
    [output appendFormat:@"%@%@: %@\n", indent, @"id", self.id];
  }
  if (self.hasName) {
    [output appendFormat:@"%@%@: %@\n", indent, @"name", self.name];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    [output appendFormat:@"%@%@: %@\n", indent, @"members", obj];
  }];
  if (self.hasAvatar) {
    [output appendFormat:@"%@%@ {\n", indent, @"avatar"];
    [self.avatar writeDescriptionTo:output
                         withIndent:[NSString stringWithFormat:@"%@  ", indent]];
    [output appendFormat:@"%@}\n", indent];
  }
  if (self.hasActive) {
    [output appendFormat:@"%@%@: %@\n", indent, @"active", [NSNumber numberWithBool:self.active]];
  }
  if (self.hasExpireTimer) {
    [output appendFormat:@"%@%@: %@\n", indent, @"expireTimer", [NSNumber numberWithInteger:self.expireTimer]];
  }
  if (self.hasColor) {
    [output appendFormat:@"%@%@: %@\n", indent, @"color", self.color];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasId) {
    [dictionary setObject: self.id forKey: @"id"];
  }
  if (self.hasName) {
    [dictionary setObject: self.name forKey: @"name"];
  }
  [dictionary setObject:self.members forKey: @"members"];
  if (self.hasAvatar) {
   NSMutableDictionary *messageDictionary = [NSMutableDictionary dictionary]; 
   [self.avatar storeInDictionary:messageDictionary];
   [dictionary setObject:[NSDictionary dictionaryWithDictionary:messageDictionary] forKey:@"avatar"];
  }
  if (self.hasActive) {
    [dictionary setObject: [NSNumber numberWithBool:self.active] forKey: @"active"];
  }
  if (self.hasExpireTimer) {
    [dictionary setObject: [NSNumber numberWithInteger:self.expireTimer] forKey: @"expireTimer"];
  }
  if (self.hasColor) {
    [dictionary setObject: self.color forKey: @"color"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoGroupDetails class]]) {
    return NO;
  }
  SSKProtoGroupDetails *otherMessage = other;
  return
      self.hasId == otherMessage.hasId &&
      (!self.hasId || [self.id isEqual:otherMessage.id]) &&
      self.hasName == otherMessage.hasName &&
      (!self.hasName || [self.name isEqual:otherMessage.name]) &&
      [self.membersArray isEqualToArray:otherMessage.membersArray] &&
      self.hasAvatar == otherMessage.hasAvatar &&
      (!self.hasAvatar || [self.avatar isEqual:otherMessage.avatar]) &&
      self.hasActive == otherMessage.hasActive &&
      (!self.hasActive || self.active == otherMessage.active) &&
      self.hasExpireTimer == otherMessage.hasExpireTimer &&
      (!self.hasExpireTimer || self.expireTimer == otherMessage.expireTimer) &&
      self.hasColor == otherMessage.hasColor &&
      (!self.hasColor || [self.color isEqual:otherMessage.color]) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasId) {
    hashCode = hashCode * 31 + [self.id hash];
  }
  if (self.hasName) {
    hashCode = hashCode * 31 + [self.name hash];
  }
  [self.membersArray enumerateObjectsUsingBlock:^(NSString *element, NSUInteger idx, BOOL *stop) {
    hashCode = hashCode * 31 + [element hash];
  }];
  if (self.hasAvatar) {
    hashCode = hashCode * 31 + [self.avatar hash];
  }
  if (self.hasActive) {
    hashCode = hashCode * 31 + [[NSNumber numberWithBool:self.active] hash];
  }
  if (self.hasExpireTimer) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.expireTimer] hash];
  }
  if (self.hasColor) {
    hashCode = hashCode * 31 + [self.color hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoGroupDetailsAvatar ()
@property (strong) NSString* contentType;
@property UInt32 length;
@end

@implementation SSKProtoGroupDetailsAvatar

- (BOOL) hasContentType {
  return !!hasContentType_;
}
- (void) setHasContentType:(BOOL) _value_ {
  hasContentType_ = !!_value_;
}
@synthesize contentType;
- (BOOL) hasLength {
  return !!hasLength_;
}
- (void) setHasLength:(BOOL) _value_ {
  hasLength_ = !!_value_;
}
@synthesize length;
- (instancetype) init {
  if ((self = [super init])) {
    self.contentType = @"";
    self.length = 0;
  }
  return self;
}
static SSKProtoGroupDetailsAvatar* defaultSSKProtoGroupDetailsAvatarInstance = nil;
+ (void) initialize {
  if (self == [SSKProtoGroupDetailsAvatar class]) {
    defaultSSKProtoGroupDetailsAvatarInstance = [[SSKProtoGroupDetailsAvatar alloc] init];
  }
}
+ (instancetype) defaultInstance {
  return defaultSSKProtoGroupDetailsAvatarInstance;
}
- (instancetype) defaultInstance {
  return defaultSSKProtoGroupDetailsAvatarInstance;
}
- (BOOL) isInitialized {
  return YES;
}
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output {
  if (self.hasContentType) {
    [output writeString:1 value:self.contentType];
  }
  if (self.hasLength) {
    [output writeUInt32:2 value:self.length];
  }
  [self.unknownFields writeToCodedOutputStream:output];
}
- (SInt32) serializedSize {
  __block SInt32 size_ = memoizedSerializedSize;
  if (size_ != -1) {
    return size_;
  }

  size_ = 0;
  if (self.hasContentType) {
    size_ += computeStringSize(1, self.contentType);
  }
  if (self.hasLength) {
    size_ += computeUInt32Size(2, self.length);
  }
  size_ += self.unknownFields.serializedSize;
  memoizedSerializedSize = size_;
  return size_;
}
+ (SSKProtoGroupDetailsAvatar*) parseFromData:(NSData*) data {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromData:data] build];
}
+ (SSKProtoGroupDetailsAvatar*) parseFromData:(NSData*) data extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromData:data extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetailsAvatar*) parseFromInputStream:(NSInputStream*) input {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromInputStream:input] build];
}
+ (SSKProtoGroupDetailsAvatar*) parseFromInputStream:(NSInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromCodedInputStream:input] build];
}
+ (SSKProtoGroupDetailsAvatar*) parseFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  return (SSKProtoGroupDetailsAvatar*)[[[SSKProtoGroupDetailsAvatar builder] mergeFromCodedInputStream:input extensionRegistry:extensionRegistry] build];
}
+ (SSKProtoGroupDetailsAvatarBuilder*) builder {
  return [[SSKProtoGroupDetailsAvatarBuilder alloc] init];
}
+ (SSKProtoGroupDetailsAvatarBuilder*) builderWithPrototype:(SSKProtoGroupDetailsAvatar*) prototype {
  return [[SSKProtoGroupDetailsAvatar builder] mergeFrom:prototype];
}
- (SSKProtoGroupDetailsAvatarBuilder*) builder {
  return [SSKProtoGroupDetailsAvatar builder];
}
- (SSKProtoGroupDetailsAvatarBuilder*) toBuilder {
  return [SSKProtoGroupDetailsAvatar builderWithPrototype:self];
}
- (void) writeDescriptionTo:(NSMutableString*) output withIndent:(NSString*) indent {
  if (self.hasContentType) {
    [output appendFormat:@"%@%@: %@\n", indent, @"contentType", self.contentType];
  }
  if (self.hasLength) {
    [output appendFormat:@"%@%@: %@\n", indent, @"length", [NSNumber numberWithInteger:self.length]];
  }
  [self.unknownFields writeDescriptionTo:output withIndent:indent];
}
- (void) storeInDictionary:(NSMutableDictionary *)dictionary {
  if (self.hasContentType) {
    [dictionary setObject: self.contentType forKey: @"contentType"];
  }
  if (self.hasLength) {
    [dictionary setObject: [NSNumber numberWithInteger:self.length] forKey: @"length"];
  }
  [self.unknownFields storeInDictionary:dictionary];
}
- (BOOL) isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[SSKProtoGroupDetailsAvatar class]]) {
    return NO;
  }
  SSKProtoGroupDetailsAvatar *otherMessage = other;
  return
      self.hasContentType == otherMessage.hasContentType &&
      (!self.hasContentType || [self.contentType isEqual:otherMessage.contentType]) &&
      self.hasLength == otherMessage.hasLength &&
      (!self.hasLength || self.length == otherMessage.length) &&
      (self.unknownFields == otherMessage.unknownFields || (self.unknownFields != nil && [self.unknownFields isEqual:otherMessage.unknownFields]));
}
- (NSUInteger) hash {
  __block NSUInteger hashCode = 7;
  if (self.hasContentType) {
    hashCode = hashCode * 31 + [self.contentType hash];
  }
  if (self.hasLength) {
    hashCode = hashCode * 31 + [[NSNumber numberWithInteger:self.length] hash];
  }
  hashCode = hashCode * 31 + [self.unknownFields hash];
  return hashCode;
}
@end

@interface SSKProtoGroupDetailsAvatarBuilder()
@property (strong) SSKProtoGroupDetailsAvatar* resultAvatar;
@end

@implementation SSKProtoGroupDetailsAvatarBuilder
@synthesize resultAvatar;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultAvatar = [[SSKProtoGroupDetailsAvatar alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultAvatar;
}
- (SSKProtoGroupDetailsAvatarBuilder*) clear {
  self.resultAvatar = [[SSKProtoGroupDetailsAvatar alloc] init];
  return self;
}
- (SSKProtoGroupDetailsAvatarBuilder*) clone {
  return [SSKProtoGroupDetailsAvatar builderWithPrototype:resultAvatar];
}
- (SSKProtoGroupDetailsAvatar*) defaultInstance {
  return [SSKProtoGroupDetailsAvatar defaultInstance];
}
- (SSKProtoGroupDetailsAvatar*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoGroupDetailsAvatar*) buildPartial {
  SSKProtoGroupDetailsAvatar* returnMe = resultAvatar;
  self.resultAvatar = nil;
  return returnMe;
}
- (SSKProtoGroupDetailsAvatarBuilder*) mergeFrom:(SSKProtoGroupDetailsAvatar*) other {
  if (other == [SSKProtoGroupDetailsAvatar defaultInstance]) {
    return self;
  }
  if (other.hasContentType) {
    [self setContentType:other.contentType];
  }
  if (other.hasLength) {
    [self setLength:other.length];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoGroupDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoGroupDetailsAvatarBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setContentType:[input readString]];
        break;
      }
      case 16: {
        [self setLength:[input readUInt32]];
        break;
      }
    }
  }
}
- (BOOL) hasContentType {
  return resultAvatar.hasContentType;
}
- (NSString*) contentType {
  return resultAvatar.contentType;
}
- (SSKProtoGroupDetailsAvatarBuilder*) setContentType:(NSString*) value {
  resultAvatar.hasContentType = YES;
  resultAvatar.contentType = value;
  return self;
}
- (SSKProtoGroupDetailsAvatarBuilder*) clearContentType {
  resultAvatar.hasContentType = NO;
  resultAvatar.contentType = @"";
  return self;
}
- (BOOL) hasLength {
  return resultAvatar.hasLength;
}
- (UInt32) length {
  return resultAvatar.length;
}
- (SSKProtoGroupDetailsAvatarBuilder*) setLength:(UInt32) value {
  resultAvatar.hasLength = YES;
  resultAvatar.length = value;
  return self;
}
- (SSKProtoGroupDetailsAvatarBuilder*) clearLength {
  resultAvatar.hasLength = NO;
  resultAvatar.length = 0;
  return self;
}
@end

@interface SSKProtoGroupDetailsBuilder()
@property (strong) SSKProtoGroupDetails* resultGroupDetails;
@end

@implementation SSKProtoGroupDetailsBuilder
@synthesize resultGroupDetails;
- (instancetype) init {
  if ((self = [super init])) {
    self.resultGroupDetails = [[SSKProtoGroupDetails alloc] init];
  }
  return self;
}
- (PBGeneratedMessage*) internalGetResult {
  return resultGroupDetails;
}
- (SSKProtoGroupDetailsBuilder*) clear {
  self.resultGroupDetails = [[SSKProtoGroupDetails alloc] init];
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clone {
  return [SSKProtoGroupDetails builderWithPrototype:resultGroupDetails];
}
- (SSKProtoGroupDetails*) defaultInstance {
  return [SSKProtoGroupDetails defaultInstance];
}
- (SSKProtoGroupDetails*) build {
  [self checkInitialized];
  return [self buildPartial];
}
- (SSKProtoGroupDetails*) buildPartial {
  SSKProtoGroupDetails* returnMe = resultGroupDetails;
  self.resultGroupDetails = nil;
  return returnMe;
}
- (SSKProtoGroupDetailsBuilder*) mergeFrom:(SSKProtoGroupDetails*) other {
  if (other == [SSKProtoGroupDetails defaultInstance]) {
    return self;
  }
  if (other.hasId) {
    [self setId:other.id];
  }
  if (other.hasName) {
    [self setName:other.name];
  }
  if (other.membersArray.count > 0) {
    if (resultGroupDetails.membersArray == nil) {
      resultGroupDetails.membersArray = [[NSMutableArray alloc] initWithArray:other.membersArray];
    } else {
      [resultGroupDetails.membersArray addObjectsFromArray:other.membersArray];
    }
  }
  if (other.hasAvatar) {
    [self mergeAvatar:other.avatar];
  }
  if (other.hasActive) {
    [self setActive:other.active];
  }
  if (other.hasExpireTimer) {
    [self setExpireTimer:other.expireTimer];
  }
  if (other.hasColor) {
    [self setColor:other.color];
  }
  [self mergeUnknownFields:other.unknownFields];
  return self;
}
- (SSKProtoGroupDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input {
  return [self mergeFromCodedInputStream:input extensionRegistry:[PBExtensionRegistry emptyRegistry]];
}
- (SSKProtoGroupDetailsBuilder*) mergeFromCodedInputStream:(PBCodedInputStream*) input extensionRegistry:(PBExtensionRegistry*) extensionRegistry {
  PBUnknownFieldSetBuilder* unknownFields = [PBUnknownFieldSet builderWithUnknownFields:self.unknownFields];
  while (YES) {
    SInt32 tag = [input readTag];
    switch (tag) {
      case 0:
        [self setUnknownFields:[unknownFields build]];
        return self;
      default: {
        if (![self parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag]) {
          [self setUnknownFields:[unknownFields build]];
          return self;
        }
        break;
      }
      case 10: {
        [self setId:[input readData]];
        break;
      }
      case 18: {
        [self setName:[input readString]];
        break;
      }
      case 26: {
        [self addMembers:[input readString]];
        break;
      }
      case 34: {
        SSKProtoGroupDetailsAvatarBuilder* subBuilder = [SSKProtoGroupDetailsAvatar builder];
        if (self.hasAvatar) {
          [subBuilder mergeFrom:self.avatar];
        }
        [input readMessage:subBuilder extensionRegistry:extensionRegistry];
        [self setAvatar:[subBuilder buildPartial]];
        break;
      }
      case 40: {
        [self setActive:[input readBool]];
        break;
      }
      case 48: {
        [self setExpireTimer:[input readUInt32]];
        break;
      }
      case 58: {
        [self setColor:[input readString]];
        break;
      }
    }
  }
}
- (BOOL) hasId {
  return resultGroupDetails.hasId;
}
- (NSData*) id {
  return resultGroupDetails.id;
}
- (SSKProtoGroupDetailsBuilder*) setId:(NSData*) value {
  resultGroupDetails.hasId = YES;
  resultGroupDetails.id = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearId {
  resultGroupDetails.hasId = NO;
  resultGroupDetails.id = [NSData data];
  return self;
}
- (BOOL) hasName {
  return resultGroupDetails.hasName;
}
- (NSString*) name {
  return resultGroupDetails.name;
}
- (SSKProtoGroupDetailsBuilder*) setName:(NSString*) value {
  resultGroupDetails.hasName = YES;
  resultGroupDetails.name = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearName {
  resultGroupDetails.hasName = NO;
  resultGroupDetails.name = @"";
  return self;
}
- (NSMutableArray *)members {
  return resultGroupDetails.membersArray;
}
- (NSString*)membersAtIndex:(NSUInteger)index {
  return [resultGroupDetails membersAtIndex:index];
}
- (SSKProtoGroupDetailsBuilder *)addMembers:(NSString*)value {
  if (resultGroupDetails.membersArray == nil) {
    resultGroupDetails.membersArray = [[NSMutableArray alloc]init];
  }
  [resultGroupDetails.membersArray addObject:value];
  return self;
}
- (SSKProtoGroupDetailsBuilder *)setMembersArray:(NSArray *)array {
  resultGroupDetails.membersArray = [[NSMutableArray alloc] initWithArray:array];
  return self;
}
- (SSKProtoGroupDetailsBuilder *)clearMembers {
  resultGroupDetails.membersArray = nil;
  return self;
}
- (BOOL) hasAvatar {
  return resultGroupDetails.hasAvatar;
}
- (SSKProtoGroupDetailsAvatar*) avatar {
  return resultGroupDetails.avatar;
}
- (SSKProtoGroupDetailsBuilder*) setAvatar:(SSKProtoGroupDetailsAvatar*) value {
  resultGroupDetails.hasAvatar = YES;
  resultGroupDetails.avatar = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) setAvatarBuilder:(SSKProtoGroupDetailsAvatarBuilder*) builderForValue {
  return [self setAvatar:[builderForValue build]];
}
- (SSKProtoGroupDetailsBuilder*) mergeAvatar:(SSKProtoGroupDetailsAvatar*) value {
  if (resultGroupDetails.hasAvatar &&
      resultGroupDetails.avatar != [SSKProtoGroupDetailsAvatar defaultInstance]) {
    resultGroupDetails.avatar =
      [[[SSKProtoGroupDetailsAvatar builderWithPrototype:resultGroupDetails.avatar] mergeFrom:value] buildPartial];
  } else {
    resultGroupDetails.avatar = value;
  }
  resultGroupDetails.hasAvatar = YES;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearAvatar {
  resultGroupDetails.hasAvatar = NO;
  resultGroupDetails.avatar = [SSKProtoGroupDetailsAvatar defaultInstance];
  return self;
}
- (BOOL) hasActive {
  return resultGroupDetails.hasActive;
}
- (BOOL) active {
  return resultGroupDetails.active;
}
- (SSKProtoGroupDetailsBuilder*) setActive:(BOOL) value {
  resultGroupDetails.hasActive = YES;
  resultGroupDetails.active = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearActive {
  resultGroupDetails.hasActive = NO;
  resultGroupDetails.active = YES;
  return self;
}
- (BOOL) hasExpireTimer {
  return resultGroupDetails.hasExpireTimer;
}
- (UInt32) expireTimer {
  return resultGroupDetails.expireTimer;
}
- (SSKProtoGroupDetailsBuilder*) setExpireTimer:(UInt32) value {
  resultGroupDetails.hasExpireTimer = YES;
  resultGroupDetails.expireTimer = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearExpireTimer {
  resultGroupDetails.hasExpireTimer = NO;
  resultGroupDetails.expireTimer = 0;
  return self;
}
- (BOOL) hasColor {
  return resultGroupDetails.hasColor;
}
- (NSString*) color {
  return resultGroupDetails.color;
}
- (SSKProtoGroupDetailsBuilder*) setColor:(NSString*) value {
  resultGroupDetails.hasColor = YES;
  resultGroupDetails.color = value;
  return self;
}
- (SSKProtoGroupDetailsBuilder*) clearColor {
  resultGroupDetails.hasColor = NO;
  resultGroupDetails.color = @"";
  return self;
}
@end


// @@protoc_insertion_point(global_scope)
