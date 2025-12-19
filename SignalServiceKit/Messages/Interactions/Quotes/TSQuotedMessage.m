//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSQuotedMessage.h"
#import "OWSPaymentMessage.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAttachmentInfo ()
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@end

@implementation OWSAttachmentInfo

- (nullable NSString *)originalAttachmentMimeType
{
    return _contentType;
}

- (nullable NSString *)originalAttachmentSourceFilename
{
    return _sourceFilename;
}

+ (NSUInteger)currentSchemaVersion
{
    return 2;
}

// MARK: -

- (instancetype)initWithOriginalAttachmentMimeType:(NSString *_Nullable)originalAttachmentMimeType
                  originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename
{
    self = [super init];
    if (self) {
        _schemaVersion = self.class.currentSchemaVersion;
        _contentType = originalAttachmentMimeType;
        _sourceFilename = originalAttachmentSourceFilename;
    }
    return self;
}

#if TESTABLE_BUILD
+ (instancetype)stubWithNullableOriginalAttachmentMimeType:(NSString *_Nullable)originalAttachmentMimeType
                          originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename
{
    return [[OWSAttachmentInfo alloc] initWithOriginalAttachmentMimeType:originalAttachmentMimeType
                                        originalAttachmentSourceFilename:originalAttachmentSourceFilename];
}
#endif

// MARK: -

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSString *attachmentId = self.attachmentId;
    if (attachmentId != nil) {
        [coder encodeObject:attachmentId forKey:@"attachmentId"];
    }
    NSString *contentType = self.contentType;
    if (contentType != nil) {
        [coder encodeObject:contentType forKey:@"contentType"];
    }
    [coder encodeObject:[self valueForKey:@"schemaVersion"] forKey:@"schemaVersion"];
    NSString *sourceFilename = self.sourceFilename;
    if (sourceFilename != nil) {
        [coder encodeObject:sourceFilename forKey:@"sourceFilename"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_attachmentId = [coder decodeObjectOfClass:[NSString class] forKey:@"attachmentId"];
    self->_contentType = [coder decodeObjectOfClass:[NSString class] forKey:@"contentType"];
    self->_schemaVersion = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                            forKey:@"schemaVersion"] unsignedIntegerValue];
    self->_sourceFilename = [coder decodeObjectOfClass:[NSString class] forKey:@"sourceFilename"];
    _schemaVersion = self.class.currentSchemaVersion;
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.attachmentId.hash;
    result ^= self.contentType.hash;
    result ^= self.schemaVersion;
    result ^= self.sourceFilename.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    OWSAttachmentInfo *typedOther = (OWSAttachmentInfo *)other;
    if (![NSObject isObject:self.attachmentId equalToObject:typedOther.attachmentId]) {
        return NO;
    }
    if (![NSObject isObject:self.contentType equalToObject:typedOther.contentType]) {
        return NO;
    }
    if (self.schemaVersion != typedOther.schemaVersion) {
        return NO;
    }
    if (![NSObject isObject:self.sourceFilename equalToObject:typedOther.sourceFilename]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSAttachmentInfo *result = [[[self class] allocWithZone:zone] init];
    result->_attachmentId = self.attachmentId;
    result->_contentType = self.contentType;
    result->_schemaVersion = self.schemaVersion;
    result->_sourceFilename = self.sourceFilename;
    return result;
}

@end

// MARK: -

@interface TSQuotedMessage ()
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, nullable) OWSAttachmentInfo *quotedAttachment;
@end

@implementation TSQuotedMessage

// Public
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
     receivedQuotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce
                           isPoll:(BOOL)isPoll
{
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = bodySource;
    _quotedAttachment = attachmentInfo;
    _isGiftBadge = isGiftBadge;
    _isTargetMessageViewOnce = isTargetMessageViewOnce;
    _isPoll = isPoll;

    return self;
}

// Public
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce
                           isPoll:(BOOL)isPoll
{
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = [timestamp unsignedLongLongValue];
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = TSQuotedMessageContentSourceLocal;
    _quotedAttachment = attachmentInfo;
    _isGiftBadge = isGiftBadge;
    _isTargetMessageViewOnce = isTargetMessageViewOnce;
    _isPoll = isPoll;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    SignalServiceAddress *authorAddress = self.authorAddress;
    if (authorAddress != nil) {
        [coder encodeObject:authorAddress forKey:@"authorAddress"];
    }
    NSString *body = self.body;
    if (body != nil) {
        [coder encodeObject:body forKey:@"body"];
    }
    MessageBodyRanges *bodyRanges = self.bodyRanges;
    if (bodyRanges != nil) {
        [coder encodeObject:bodyRanges forKey:@"bodyRanges"];
    }
    [coder encodeObject:[self valueForKey:@"bodySource"] forKey:@"bodySource"];
    [coder encodeObject:[self valueForKey:@"isGiftBadge"] forKey:@"isGiftBadge"];
    [coder encodeObject:[self valueForKey:@"isPoll"] forKey:@"isPoll"];
    [coder encodeObject:[self valueForKey:@"isTargetMessageViewOnce"] forKey:@"isTargetMessageViewOnce"];
    OWSAttachmentInfo *quotedAttachment = self.quotedAttachment;
    if (quotedAttachment != nil) {
        [coder encodeObject:quotedAttachment forKey:@"quotedAttachment"];
    }
    [coder encodeObject:[self valueForKey:@"timestamp"] forKey:@"timestamp"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_authorAddress = [coder decodeObjectOfClass:[SignalServiceAddress class] forKey:@"authorAddress"];
    self->_body = [coder decodeObjectOfClass:[NSString class] forKey:@"body"];
    self->_bodyRanges = [coder decodeObjectOfClass:[MessageBodyRanges class] forKey:@"bodyRanges"];
    self->_bodySource = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                         forKey:@"bodySource"] unsignedIntegerValue];
    self->_isGiftBadge = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isGiftBadge"] boolValue];
    self->_isPoll = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"isPoll"] boolValue];
    self->_isTargetMessageViewOnce = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                      forKey:@"isTargetMessageViewOnce"] boolValue];
    self->_quotedAttachment = [coder decodeObjectOfClass:[OWSAttachmentInfo class] forKey:@"quotedAttachment"];
    self->_timestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                        forKey:@"timestamp"] unsignedLongLongValue];

    if (_authorAddress == nil) {
        NSString *phoneNumber = [coder decodeObjectForKey:@"authorId"];
        _authorAddress = [SignalServiceAddress legacyAddressWithServiceIdString:nil phoneNumber:phoneNumber];
        OWSAssertDebug(_authorAddress.isValid);
    }

    if (_quotedAttachment == nil) {
        NSSet *expectedClasses = [NSSet setWithArray:@[ [NSArray class], [OWSAttachmentInfo class] ]];
        NSArray *_Nullable attachmentInfos = [coder decodeObjectOfClasses:expectedClasses forKey:@"quotedAttachments"];

        if ([attachmentInfos.firstObject isKindOfClass:[OWSAttachmentInfo class]]) {
            // In practice, we only used the first item of this array
            OWSAssertDebug(attachmentInfos.count <= 1);
            _quotedAttachment = attachmentInfos.firstObject;
        }
    }

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.authorAddress.hash;
    result ^= self.body.hash;
    result ^= self.bodyRanges.hash;
    result ^= self.bodySource;
    result ^= self.isGiftBadge;
    result ^= self.isPoll;
    result ^= self.isTargetMessageViewOnce;
    result ^= self.quotedAttachment.hash;
    result ^= self.timestamp;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSQuotedMessage *typedOther = (TSQuotedMessage *)other;
    if (![NSObject isObject:self.authorAddress equalToObject:typedOther.authorAddress]) {
        return NO;
    }
    if (![NSObject isObject:self.body equalToObject:typedOther.body]) {
        return NO;
    }
    if (![NSObject isObject:self.bodyRanges equalToObject:typedOther.bodyRanges]) {
        return NO;
    }
    if (self.bodySource != typedOther.bodySource) {
        return NO;
    }
    if (self.isGiftBadge != typedOther.isGiftBadge) {
        return NO;
    }
    if (self.isPoll != typedOther.isPoll) {
        return NO;
    }
    if (self.isTargetMessageViewOnce != typedOther.isTargetMessageViewOnce) {
        return NO;
    }
    if (![NSObject isObject:self.quotedAttachment equalToObject:typedOther.quotedAttachment]) {
        return NO;
    }
    if (self.timestamp != typedOther.timestamp) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSQuotedMessage *result = [[[self class] allocWithZone:zone] init];
    result->_authorAddress = self.authorAddress;
    result->_body = self.body;
    result->_bodyRanges = self.bodyRanges;
    result->_bodySource = self.bodySource;
    result->_isGiftBadge = self.isGiftBadge;
    result->_isPoll = self.isPoll;
    result->_isTargetMessageViewOnce = self.isTargetMessageViewOnce;
    result->_quotedAttachment = self.quotedAttachment;
    result->_timestamp = self.timestamp;
    return result;
}

+ (instancetype)quotedMessageFromBackupWithTargetMessageTimestamp:(nullable NSNumber *)timestamp
                                                    authorAddress:(SignalServiceAddress *)authorAddress
                                                             body:(nullable NSString *)body
                                                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                                                       bodySource:(TSQuotedMessageContentSource)bodySource
                                             quotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                                                      isGiftBadge:(BOOL)isGiftBadge
                                          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce
                                                           isPoll:(BOOL)isPoll
{
    OWSAssertDebug(authorAddress.isValid);

    uint64_t rawTimestamp;
    rawTimestamp = [timestamp unsignedLongLongValue];

    return [[TSQuotedMessage alloc] initWithTimestamp:rawTimestamp
                                        authorAddress:authorAddress
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:bodySource
                         receivedQuotedAttachmentInfo:attachmentInfo
                                          isGiftBadge:isGiftBadge
                              isTargetMessageViewOnce:isTargetMessageViewOnce
                                               isPoll:isPoll];
}

- (nullable NSNumber *)getTimestampValue
{
    return [self timestampValue];
}

- (nullable NSNumber *)timestampValue
{
    if (_timestamp == 0) {
        return nil;
    }
    return [[NSNumber alloc] initWithUnsignedLongLong:_timestamp];
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable OWSAttachmentInfo *)attachmentInfo
{
    return _quotedAttachment;
}

@end

NS_ASSUME_NONNULL_END
