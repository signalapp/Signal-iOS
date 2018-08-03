//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSTableSection;
@class CNContact;

@interface DebugUIContacts : DebugUIPage

+ (void)createRandomContacts:(NSUInteger)count
              contactHandler:
                  (nullable void (^)(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop))contactHandler;

@end

NS_ASSUME_NONNULL_END
