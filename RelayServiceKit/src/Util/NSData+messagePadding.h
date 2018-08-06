//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface NSData (messagePadding)

- (NSData *)removePadding;

- (NSData *)paddedMessageBody;

@end
