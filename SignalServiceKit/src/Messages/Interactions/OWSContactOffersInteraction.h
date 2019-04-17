//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInteraction.h>

@class YapDatabaseReadWriteTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction : TSInteraction

@property (nonatomic, readonly) BOOL hasBlockOffer;
@property (nonatomic, readonly) BOOL hasAddToContactsOffer;
@property (nonatomic, readonly) BOOL hasAddToProfileWhitelistOffer;

// TODO - remove this recipientId param
// it's redundant with the interaction's TSContactThread
@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) NSString *beforeInteractionId;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// MJK TODO should be safe to remove this timestamp param
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                                  timestamp:(uint64_t)timestamp
                                     thread:(TSThread *)thread
                              hasBlockOffer:(BOOL)hasBlockOffer
                      hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
              hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                                recipientId:(NSString *)recipientId
                        beforeInteractionId:(NSString *)beforeInteractionId NS_DESIGNATED_INITIALIZER;

// --- CODE GENERATION MARKER

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(unsigned long long)receivedAtTimestamp
                          sortId:(unsigned long long)sortId
                       timestamp:(unsigned long long)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
             beforeInteractionId:(NSString *)beforeInteractionId
           hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
   hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
                   hasBlockOffer:(BOOL)hasBlockOffer
                     recipientId:(NSString *)recipientId
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:beforeInteractionId:hasAddToContactsOffer:hasAddToProfileWhitelistOffer:hasBlockOffer:recipientId:));

// clang-format on

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
