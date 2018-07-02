//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;

@interface OWSContactShareView : UIView

- (instancetype)initWithContactShare:(ContactShareViewModel *)contactShare isIncoming:(BOOL)isIncoming;

- (void)createContents;

+ (CGFloat)bubbleHeight;

@end

NS_ASSUME_NONNULL_END
