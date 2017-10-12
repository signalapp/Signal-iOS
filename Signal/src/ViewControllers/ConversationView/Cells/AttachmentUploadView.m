//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AttachmentUploadView.h"
#import "OWSProgressView.h"
#import "OWSUploadingService.h"
#import "TSAttachmentStream.h"

NS_ASSUME_NONNULL_BEGIN

@interface AttachmentUploadView ()

@property (nonatomic) TSAttachmentStream *attachment;

@property (nonatomic) OWSProgressView *progressView;

@property (nonatomic) CALayer *maskLayer;

@property (nonatomic) AttachmentStateBlock _Nullable attachmentStateCallback;

@property (nonatomic) BOOL isAttachmentReady;

@property (nonatomic) CGFloat lastProgress;

@end

#pragma mark -

@implementation AttachmentUploadView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                         superview:(UIView *)superview
           attachmentStateCallback:(AttachmentStateBlock _Nullable)attachmentStateCallback
{
    self = [super init];

    if (self) {
        OWSAssert(attachment);
        OWSAssert(superview);

        self.attachment = attachment;
        self.attachmentStateCallback = attachmentStateCallback;

        _maskLayer = [CALayer layer];
        [_maskLayer setBackgroundColor:[UIColor blackColor].CGColor];
        [_maskLayer setOpacity:0.4f];
        [_maskLayer setFrame:superview.frame];
        [superview.layer addSublayer:_maskLayer];

        const CGFloat progressWidth = round(superview.frame.size.width * 0.45f);
        const CGFloat progressHeight = round(MIN(superview.frame.size.height * 0.5f, progressWidth * 0.09f));
        CGRect progressFrame = CGRectMake(round((superview.frame.size.width - progressWidth) * 0.5f),
            round((superview.frame.size.height - progressHeight) * 0.5f),
            progressWidth,
            progressHeight);
        // The progress view is white.  It will only be shown
        // while the mask layer is visible, so it will show up
        // even against all-white attachments.
        _progressView = [OWSProgressView new];
        _progressView.color = [UIColor whiteColor];
        _progressView.frame = progressFrame;
        [superview addSubview:_progressView];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(attachmentUploadProgress:)
                                                     name:kAttachmentUploadProgressNotification
                                                   object:nil];

        _isAttachmentReady = self.attachment.isUploaded;

        [self ensureViewState];

        if (attachmentStateCallback) {
            self.attachmentStateCallback(_isAttachmentReady);
        }
    }
    return self;
}

- (void)dealloc
{
    [_maskLayer removeFromSuperlayer];
    [_progressView removeFromSuperview];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIsAttachmentReady:(BOOL)isAttachmentReady
{
    if (_isAttachmentReady == isAttachmentReady) {
        return;
    }

    _isAttachmentReady = isAttachmentReady;

    [self ensureViewState];

    if (self.attachmentStateCallback) {
        self.attachmentStateCallback(isAttachmentReady);
    }
}

- (void)setLastProgress:(CGFloat)lastProgress
{
    _lastProgress = lastProgress;

    [self ensureViewState];
}

- (void)ensureViewState
{
    _maskLayer.hidden = self.isAttachmentReady || self.lastProgress == 0;
    _progressView.hidden = self.isAttachmentReady || self.lastProgress == 0;
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];
    if ([self.attachment.uniqueId isEqual:attachmentID]) {
        if (!isnan(progress)) {
            [_progressView setProgress:progress];
            self.lastProgress = progress;
            self.isAttachmentReady = self.attachment.isUploaded;
        } else {
            OWSFail(@"%@ Invalid attachment progress.", self.tag);
            self.isAttachmentReady = YES;
        }
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
