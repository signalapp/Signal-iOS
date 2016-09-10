//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSChunkedOutputStream.h"

NS_ASSUME_NONNULL_BEGIN

@class Contact;

@interface OWSContactsOutputStream : OWSChunkedOutputStream

- (void)writeContact:(Contact *)contact;

@end

NS_ASSUME_NONNULL_END
