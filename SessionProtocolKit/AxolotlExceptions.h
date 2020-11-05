//
//  AxolotlExceptions.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 23/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#ifndef AxolotlKit_AxolotlExceptions_h
#define AxolotlKit_AxolotlExceptions_h

/**
 *  Thrown when the user is:
 
 1) Sending a message with a PreKeyBundle that contains a different identity key than the previously known one.
 2) Receiving a new PreKeyWhisperMessage that has a different identity key than the previously known one.
 */

static NSString *UntrustedIdentityKeyException = @"AxolotlUnstrustedIdentityKeyException";

/**
 *  Thrown thrown when a message is received with an unknown PreKeyID.
 */

static NSString *InvalidKeyIdException         = @"AxolotlInvalidKeyIdException";

/**
 *  Thrown when:
 
 1) Signature of Prekeys are not correctly signed.
 2) We received a key type that is not compatible with this version. (All keys should be Curve25519).
 */

static NSString *InvalidKeyException           = @"AxolotlInvalidKeyException";

/**
 *  Thrown when receiving a message with no associated session for decryption.
 */

static NSString *NoSessionException            = @"AxolotlNoSessionException";

/**
 *  Thrown when receiving a malformatted message.
 */

static NSString *InvalidMessageException       = @"AxolotlInvalidMessageException";

/**
 *  Thrown when experiencing issues encrypting/decrypting a message symetrically.
 */

static NSString *CipherException               = @"AxolotlCipherIssue";

/**
 *  Thrown when detecting a message being sent a second time. (Replay attacks/bugs)
 */

static NSString *DuplicateMessageException     = @"AxolotlDuplicateMessage";

/**
 *  Thrown when receiving a message send with a non-supported version of the TextSecure protocol.
 */

static NSString *LegacyMessageException        = @"AxolotlLegacyMessageException";

/**
 *  Thrown when a client tries to initiate a session with a non-supported version.
 */

static NSString *InvalidVersionException       = @"AxolotlInvalidVersionException";

#endif
