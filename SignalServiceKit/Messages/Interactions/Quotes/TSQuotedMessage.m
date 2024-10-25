//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSQuotedMessage.h"
#import "OWSPaymentMessage.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
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

- (nullable NSString *)attachmentId
{
    return _rawAttachmentId.ows_nilIfEmpty;
}

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
    return 1;
}

// MARK: -

+ (instancetype)stubWithOriginalAttachmentMimeType:(NSString *)originalAttachmentMimeType
                  originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename
{
    return [[OWSAttachmentInfo alloc] initWithAttachmentId:nil
                                                    ofType:OWSAttachmentInfoReferenceUnset
                                originalAttachmentMimeType:originalAttachmentMimeType
                          originalAttachmentSourceFilename:originalAttachmentSourceFilename];
}

+ (instancetype)forV2ThumbnailReferenceWithOriginalAttachmentMimeType:(NSString *)originalAttachmentMimeType
                                     originalAttachmentSourceFilename:
                                         (NSString *_Nullable)originalAttachmentSourceFilename
{
    return [[OWSAttachmentInfo alloc] initWithAttachmentId:nil
                                                    ofType:OWSAttachmentInfoReferenceV2
                                originalAttachmentMimeType:originalAttachmentMimeType
                          originalAttachmentSourceFilename:originalAttachmentSourceFilename];
}

+ (instancetype)withLegacyAttachmentId:(NSString *)attachmentId
                                ofType:(OWSAttachmentInfoReference)attachmentType
            originalAttachmentMimeType:(NSString *)originalAttachmentMimeType
      originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename
{
    return [[OWSAttachmentInfo alloc] initWithAttachmentId:attachmentId
                                                    ofType:attachmentType
                                originalAttachmentMimeType:originalAttachmentMimeType
                          originalAttachmentSourceFilename:originalAttachmentSourceFilename];
}

- (instancetype)initWithAttachmentId:(NSString *_Nullable)attachmentId
                              ofType:(OWSAttachmentInfoReference)attachmentType
          originalAttachmentMimeType:(NSString *_Nullable)originalAttachmentMimeType
    originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename
{
    self = [super init];
    if (self) {
        _schemaVersion = self.class.currentSchemaVersion;
        _rawAttachmentId = attachmentId;
        _attachmentType = attachmentType;
        _contentType = originalAttachmentMimeType;
        _sourceFilename = originalAttachmentSourceFilename;
    }
    return self;
}

// MARK: -

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_schemaVersion == 0) {
        NSString *_Nullable oldStreamId = [coder decodeObjectOfClass:[NSString class]
                                                              forKey:@"thumbnailAttachmentStreamId"];
        NSString *_Nullable oldPointerId = [coder decodeObjectOfClass:[NSString class]
                                                               forKey:@"thumbnailAttachmentPointerId"];
        NSString *_Nullable oldSourceAttachmentId = [coder decodeObjectOfClass:[NSString class] forKey:@"attachmentId"];

        // Before, we maintained each of these IDs in parallel, though in practice only one in use at a time.
        // Migration codifies this behavior.
        if (oldStreamId && [oldPointerId isEqualToString:oldStreamId]) {
            _attachmentType = OWSAttachmentInfoReferenceThumbnail;
            _rawAttachmentId = oldStreamId;
        } else if (oldPointerId) {
            _attachmentType = OWSAttachmentInfoReferenceUntrustedPointer;
            _rawAttachmentId = oldPointerId;
        } else if (oldStreamId) {
            _attachmentType = OWSAttachmentInfoReferenceThumbnail;
            _rawAttachmentId = oldStreamId;
        } else if (oldSourceAttachmentId) {
            _attachmentType = OWSAttachmentInfoReferenceOriginalForSend;
            _rawAttachmentId = oldSourceAttachmentId;
        } else {
            _attachmentType = OWSAttachmentInfoReferenceUnset;
            _rawAttachmentId = nil;
        }
    }
    _schemaVersion = self.class.currentSchemaVersion;
    return self;
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

    return self;
}

// Public
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    if (timestamp) {
        OWSAssertDebug(timestamp > 0);
        _timestamp = [timestamp unsignedLongLongValue];
    } else {
        _timestamp = 0;
    }
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = TSQuotedMessageContentSourceLocal;
    _quotedAttachment = attachmentInfo;
    _isGiftBadge = isGiftBadge;

    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

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

+ (instancetype)quotedMessageWithTargetMessageTimestamp:(nullable NSNumber *)timestamp
                                          authorAddress:(SignalServiceAddress *)authorAddress
                                                   body:(nullable NSString *)body
                                             bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                                             bodySource:(TSQuotedMessageContentSource)bodySource
                                   quotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                                            isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(body != nil || attachmentInfo != nil || isGiftBadge);
    OWSAssertDebug(authorAddress.isValid);

    uint64_t rawTimestamp;
    if (timestamp) {
        OWSAssertDebug(timestamp > 0);
        rawTimestamp = [timestamp unsignedLongLongValue];
    } else {
        rawTimestamp = 0;
    }

    return [[TSQuotedMessage alloc] initWithTimestamp:rawTimestamp
                                        authorAddress:authorAddress
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:bodySource
                         receivedQuotedAttachmentInfo:attachmentInfo
                                          isGiftBadge:isGiftBadge];
}

- (nullable NSNumber *)getTimestampValue
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

- (void)setLegacyThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    self.quotedAttachment.attachmentType = OWSAttachmentInfoReferenceThumbnail;
    self.quotedAttachment.rawAttachmentId = attachmentStream.uniqueId;
}

@end

NS_ASSUME_NONNULL_END
