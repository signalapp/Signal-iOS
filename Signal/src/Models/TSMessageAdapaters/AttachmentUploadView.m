//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AttachmentUploadView.h"
#import "OWSProgressView.h"
#import "OWSUploadingService.h"
#import "TSAttachmentStream.h"

@interface AttachmentUploadView ()

@property (nonatomic) TSAttachmentStream *attachment;

@property (nonatomic) OWSProgressView *progressView;

@property (nonatomic) CALayer *maskLayer;

@property (nonatomic) AttachmentStateBlock attachmentStateCallback;

@property (nonatomic) BOOL isAttachmentReady;

@end

#pragma mark -

@implementation AttachmentUploadView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                         superview:(UIView *)superview
           attachmentStateCallback:(AttachmentStateBlock)attachmentStateCallback
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
        const CGFloat progressHeight = round(progressWidth * 0.11f);
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

- (void)ensureViewState
{
    _maskLayer.hidden = self.isAttachmentReady;
    _progressView.hidden = self.isAttachmentReady;
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];
    if ([self.attachment.uniqueId isEqualToString:attachmentID]) {
        if (!isnan(progress)) {
            [_progressView setProgress:(float)progress];
            self.isAttachmentReady = self.attachment.isUploaded;
        } else {
            self.isAttachmentReady = YES;
        }
    }
}

@end
