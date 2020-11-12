//
//  TSMessageKeys.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 09/03/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MessageKeys : NSObject <NSSecureCoding>

- (instancetype)initWithCipherKey:(NSData*)cipherKey macKey:(NSData*)macKey iv:(NSData*)data index:(int)index;

@property (readonly)NSData *cipherKey;
@property (readonly)NSData *macKey;
@property (readonly)NSData *iv;
@property (readonly)int    index;

@end
