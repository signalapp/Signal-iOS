//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AttachmentUploadView.h"
#import "OWSBezierPathView.h"
#import "OWSProgressView.h"
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/OWSUploadOperation.h>
#import <SignalServiceKit/TSAttachmentStream.h>

NS_ASSUME_NONNULL_BEGIN

@interface AttachmentUploadView ()

@property (nonatomic) TSAttachmentStream *attachment;

@property (nonatomic) OWSProgressView *progressView;

@property (nonatomic) UILabel *progressLabel;

@property (nonatomic) AttachmentStateBlock _Nullable attachmentStateCallback;

@property (nonatomic) BOOL isAttachmentReady;

@property (nonatomic) CGFloat lastProgress;

@end

#pragma mark -

@implementation AttachmentUploadView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
           attachmentStateCallback:(AttachmentStateBlock _Nullable)attachmentStateCallback
{
    self = [super init];

    if (self) {
        OWSAssertDebug(attachment);

        self.attachment = attachment;
        self.attachmentStateCallback = attachmentStateCallback;

        [self createContents];

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

- (void)createContents
{
    // The progress view is white.  It will only be shown
    // while the mask layer is visible, so it will show up
    // even against all-white attachments.
    _progressView = [OWSProgressView new];
    self.progressView.color = [UIColor whiteColor];
    [self.progressView autoSetDimension:ALDimensionWidth toSize:80.f];
    [self.progressView autoSetDimension:ALDimensionHeight toSize:6.f];

    self.progressLabel = [UILabel new];
    self.progressLabel.text = NSLocalizedString(
        @"MESSAGE_METADATA_VIEW_MESSAGE_STATUS_UPLOADING", @"Status label for messages which are uploading.")
                                  .localizedUppercaseString;
    self.progressLabel.textColor = UIColor.whiteColor;
    self.progressLabel.font = [UIFont ows_dynamicTypeCaption1Font];
    self.progressLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.progressView,
        self.progressLabel,
    ]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 4;
    stackView.layoutMargins = UIEdgeInsetsMake(4, 4, 4, 4);
    stackView.layoutMarginsRelativeArrangement = YES;
    [self addSubview:stackView];
    [stackView autoCenterInSuperview];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTrailing relation:NSLayoutRelationGreaterThanOrEqual];
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
    BOOL isUploading = !self.isAttachmentReady && self.lastProgress != 0;
    self.backgroundColor = (isUploading ? [UIColor colorWithWhite:0.f alpha:0.2f] : nil);
    self.progressView.hidden = !isUploading;
    self.progressLabel.hidden = !isUploading;
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];
    if ([self.attachment.uniqueId isEqual:attachmentID]) {
        if (!isnan(progress)) {
            [self.progressView setProgress:(CGFloat)progress];
            self.lastProgress = (CGFloat)progress;
            self.isAttachmentReady = self.attachment.isUploaded;
        } else {
            OWSFailDebug(@"Invalid attachment progress.");
            self.isAttachmentReady = YES;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
