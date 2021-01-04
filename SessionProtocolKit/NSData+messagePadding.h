//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface NSData (messagePadding)

- (NSData *)removePadding;

- (NSData *)paddedMessageBody;

@end
