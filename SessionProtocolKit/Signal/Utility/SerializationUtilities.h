//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define MAC_LENGTH 8

@interface SerializationUtilities : NSObject

+ (int)highBitsToIntFromByte:(Byte)byte;

+ (int)lowBitsToIntFromByte:(Byte)byte;

+ (Byte)intsToByteHigh:(int)highValue low:(int)lowValue;

+ (NSData *)throws_macWithVersion:(int)version
                      identityKey:(NSData *)senderIdentityKey
              receiverIdentityKey:(NSData *)receiverIdentityKey
                           macKey:(NSData *)macKey
                       serialized:(NSData *)serialized NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

NS_ASSUME_NONNULL_END
