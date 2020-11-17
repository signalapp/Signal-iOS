//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "IdentityKeyStore.h"
#import "PreKeyStore.h"
#import "SessionStore.h"
#import "SignedPreKeyStore.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  The Session Store defines the interface of the storage of sesssions.
 */

@protocol AxolotlStore <SessionStore, IdentityKeyStore, PreKeyStore, SessionStore, SignedPreKeyStore>

@end

NS_ASSUME_NONNULL_END
