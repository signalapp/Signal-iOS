//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

@interface LegacyMessageKeys : NSObject <NSSecureCoding>

- (instancetype)initWithCipherKey:(NSData*)cipherKey macKey:(NSData*)macKey iv:(NSData*)data index:(int)index;

@property (readonly)NSData *cipherKey;
@property (readonly)NSData *macKey;
@property (readonly)NSData *iv;
@property (readonly)int    index;

@end
