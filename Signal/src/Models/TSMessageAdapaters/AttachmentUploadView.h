//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

typedef void (^AttachmentStateBlock)(BOOL isAttachmentReady);

// This entity is used by various attachment adapters to
// coordinate view state with attachment uploads.
// During attachment uploads we want to:
//
// * Dim the media view using a mask layer.
// * Show and update a progress bar.
// * Disable any media view controls using a callback.
@interface AttachmentUploadView : NSObject

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                         superview:(UIView *)superview
           attachmentStateCallback:(AttachmentStateBlock _Nullable)attachmentStateCallback;

@end

NS_ASSUME_NONNULL_END
