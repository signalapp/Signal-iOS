//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface OWSGenericAttachmentView : UIView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream isIncoming:(BOOL)isIncoming;

- (void)createContents;

+ (CGFloat)bubbleHeight;

@end

NS_ASSUME_NONNULL_END
