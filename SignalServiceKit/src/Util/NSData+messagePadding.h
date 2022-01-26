//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Foundation/NSData.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (messagePadding)

- (NSData *)removePadding;

- (NSData *)paddedMessageBody;

@end

NS_ASSUME_NONNULL_END
