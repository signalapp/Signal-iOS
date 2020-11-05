//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;

typedef NS_ENUM(NSInteger, TSMessageDirection) {
    TSMessageDirectionUnknown = 0,
    TSMessageDirectionIncoming,
    TSMessageDirectionOutgoing
};

// See a discussion of the protocolContext in SessionCipher.h.
@protocol IdentityKeyStore <NSObject>

- (nullable ECKeyPair *)identityKeyPair:(nullable id)protocolContext;

- (int)localRegistrationId:(nullable id)protocolContext;

/**
 * Record a recipients identity key
 *
 * @param   identityKey key data used to identify the recipient
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 *
 * @returns YES if we are replacing an existing known identity key for recipientId.
 *          NO  if there was no previously stored identity key for the recipient.
 */
- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
           protocolContext:(nullable id)protocolContext;

/**
 * @param   identityKey key data used to identify the recipient
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 * @param   direction   whether the key is being used in a sending or receiving context, as this could affect the
 *                      decision to trust the key.
 *
 * @returns YES if the key is trusted
 *          NO  if the key is not trusted
 */
- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
             protocolContext:(nullable id)protocolContext;

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId;

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId protocolContext:(nullable id)protocolContext;

@end

NS_ASSUME_NONNULL_END
