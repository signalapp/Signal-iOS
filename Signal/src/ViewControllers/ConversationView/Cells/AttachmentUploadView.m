//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AttachmentUploadView.h"
#import "OWSBezierPathView.h"
#import "OWSProgressView.h"
#import "OWSUploadingService.h"
#import "TSAttachmentStream.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface AttachmentUploadView ()

@property (nonatomic) TSAttachmentStream *attachment;

@property (nonatomic) OWSBezierPathView *bezierPathView;

@property (nonatomic) OWSProgressView *progressView;

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

        [superview addSubview:self];
        [self autoPinToSuperviewEdges];

        _bezierPathView = [OWSBezierPathView new];
        self.bezierPathView.configureShapeLayerBlock = ^(CAShapeLayer *layer, CGRect bounds) {
            layer.path = [UIBezierPath bezierPathWithRect:bounds].CGPath;
            layer.fillColor = [UIColor colorWithWhite:0.f alpha:0.4f].CGColor;
        };
        [self addSubview:self.bezierPathView];
        [self.bezierPathView autoPinToSuperviewEdges];

        // The progress view is white.  It will only be shown
        // while the mask layer is visible, so it will show up
        // even against all-white attachments.
        _progressView = [OWSProgressView new];
        self.progressView.color = [UIColor whiteColor];
        [self addSubview:self.progressView];

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

- (void)setLastProgress:(CGFloat)lastProgress
{
    _lastProgress = lastProgress;

    [self ensureViewState];
}

- (void)ensureViewState
{
    self.bezierPathView.hidden = self.isAttachmentReady || self.lastProgress == 0;
    self.progressView.hidden = self.isAttachmentReady || self.lastProgress == 0;
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];
    if ([self.attachment.uniqueId isEqual:attachmentID]) {
        if (!isnan(progress)) {
            [self.progressView setProgress:progress];
            self.lastProgress = progress;
            self.isAttachmentReady = self.attachment.isUploaded;
        } else {
            OWSFail(@"%@ Invalid attachment progress.", self.logTag);
            self.isAttachmentReady = YES;
        }
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL sizeDidChange = !CGSizeEqualToSize(bounds.size, self.bounds.size);
    [super setBounds:bounds];
    if (sizeDidChange) {
        [self updateLayout];
    }
}

- (void)setFrame:(CGRect)frame
{
    BOOL sizeDidChange = !CGSizeEqualToSize(frame.size, self.frame.size);
    [super setFrame:frame];
    if (sizeDidChange) {
        [self updateLayout];
    }
}

- (void)updateLayout
{
    // Center the progress bar within the bubble mask.
    //
    // TODO: Verify that this layout works in RTL.
    const CGFloat kBubbleTailWidth = 6.f;
    CGRect bounds = self.bounds;
    bounds.size.width -= kBubbleTailWidth;
    if (self.isRTL) {
        bounds.origin.x += kBubbleTailWidth;
    }

    const CGFloat progressWidth = round(bounds.size.width * 0.45f);
    const CGFloat progressHeight = round(MIN(bounds.size.height * 0.5f, progressWidth * 0.09f));
    CGRect progressFrame = CGRectMake(round(bounds.origin.x + (bounds.size.width - progressWidth) * 0.5f),
        round(bounds.origin.y + (bounds.size.height - progressHeight) * 0.5f),
        progressWidth,
        progressHeight);
    self.progressView.frame = progressFrame;
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
