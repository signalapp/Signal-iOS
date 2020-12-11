//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const UIDataDetectorTypes kOWSAllowedDataDetectorTypes;
extern const UIDataDetectorTypes kOWSAllowedDataDetectorTypesExceptLinks;

@interface OWSTextView : UITextView

- (void)ensureShouldLinkifyText:(BOOL)shouldLinkifyText;

@end

NS_ASSUME_NONNULL_END
