//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioMessageView.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAudioMessageView ()

@property (nonatomic) TSAttachment *attachment;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic) BOOL isIncoming;
@property (nonatomic, weak) id<ConversationViewItem> viewItem;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, nullable) UIButton *audioPlayPauseButton;
@property (nonatomic, nullable) UILabel *playbackTimeLabel;
@property (nonatomic, nullable) UISlider *audioProgressSlider;
@property (nonatomic, nullable) AudioWaveformProgressView *waveformProgressView;

@end

#pragma mark -

@implementation OWSAudioMessageView

- (instancetype)initWithAttachment:(TSAttachment *)attachment
                        isIncoming:(BOOL)isIncoming
                          viewItem:(id<ConversationViewItem>)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle
{
    self = [super init];

    if (self) {
        _attachment = attachment;
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            _attachmentStream = (TSAttachmentStream *)attachment;
        }
        _isIncoming = isIncoming;
        _viewItem = viewItem;
        _conversationStyle = conversationStyle;
    }

    return self;
}

- (void)updateContents
{
    if (self.audioPlaybackState == AudioPlaybackState_Playing) {
        [self setAudioIconToPause];
    } else {
        [self setAudioIconToPlay];
    }

    // Don't update the position if we're current scrubbing, as it conflicts with the user interaction.
    if (!self.isScrubbing) {
        [self updateWaveformProgressView];
        [self updateAudioBottomLabel:self.audioProgressSeconds];
    }
}

- (CGFloat)audioProgressSeconds
{
    return [self.viewItem audioProgressSeconds];
}

- (CGFloat)audioDurationSeconds
{
    return self.viewItem.audioDurationSeconds;
}

- (AudioPlaybackState)audioPlaybackState
{
    return [self.viewItem audioPlaybackState];
}

- (BOOL)isAudioPlaying
{
    return self.audioPlaybackState == AudioPlaybackState_Playing;
}

- (void)updateAudioBottomLabel:(CGFloat)progressSeconds
{
    self.playbackTimeLabel.text =
        [OWSFormat formatDurationSeconds:(long)round(self.audioDurationSeconds - progressSeconds)];
}

- (void)setAudioIcon:(UIImage *)icon
{
    OWSAssertDebug(icon.size.height == self.iconSize);

    icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateNormal];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateDisabled];
}

- (void)setAudioIconToPlay
{
    [self setAudioIcon:[UIImage imageNamed:@"play-filled-24"]];
}

- (void)setAudioIconToPause
{
    [self setAudioIcon:[UIImage imageNamed:@"pause-filled-24"]];
}

- (void)updateWaveformProgressView
{
    float progressRatio = 0;
    if (self.audioDurationSeconds > 0) {
        progressRatio = (float)(self.audioProgressSeconds / self.audioDurationSeconds);
    }

    [self setProgressRatio:progressRatio];

    UIColor *playedColor = nil;
    UIColor *unplayedColor = nil;
    UIColor *thumbColor = nil;

    if (self.isIncoming) {
        playedColor = [UIColor colorWithRGBHex:0x92caff];
        unplayedColor = [[Theme secondaryColor] colorWithAlphaComponent:0.3];
        thumbColor = [Theme secondaryColor];
    } else {
        playedColor = [UIColor ows_whiteColor];
        unplayedColor = [[UIColor ows_whiteColor] colorWithAlphaComponent:0.6];
        thumbColor = [UIColor ows_whiteColor];
    }

    [self.audioProgressSlider
        setThumbImage:[[UIImage imageNamed:@"audio_message_thumb"] asTintedImageWithColor:thumbColor]
             forState:UIControlStateNormal];
    [self.audioProgressSlider setMinimumTrackImage:[self trackImageWithColor:playedColor]
                                          forState:UIControlStateNormal];
    [self.audioProgressSlider setMaximumTrackImage:[self trackImageWithColor:unplayedColor]
                                          forState:UIControlStateNormal];

    self.audioPlayPauseButton.imageView.tintColor = thumbColor;

    self.waveformProgressView.playedColor = playedColor;
    self.waveformProgressView.unplayedColor = unplayedColor;
    self.waveformProgressView.thumbColor = thumbColor;
    self.waveformProgressView.audioWaveform = self.viewItem.audioWaveform;

    self.audioProgressSlider.hidden = self.viewItem.audioWaveform != nil;
    self.waveformProgressView.hidden = self.viewItem.audioWaveform == nil;
}

- (void)setProgressRatio:(float)progressRatio
{
    [self.audioProgressSlider setValue:progressRatio];
    self.waveformProgressView.value = progressRatio;
}

- (UIImage *)trackImageWithColor:(UIColor *)color
{
    return [[[UIImage imageNamed:@"audio_message_track"] asTintedImageWithColor:color]
        resizableImageWithCapInsets:UIEdgeInsetsMake(0, 2, 0, 2)];
}

- (void)replaceIconWithDownloadProgressIfNecessary:(UIView *)iconView
{
    if (!self.viewItem.attachmentPointer) {
        return;
    }

    switch (self.viewItem.attachmentPointer.state) {
        case TSAttachmentPointerStateFailed:
            // We don't need to handle the "tap to retry" state here,
            // only download progress.
            return;
        case TSAttachmentPointerStateEnqueued:
        case TSAttachmentPointerStateDownloading:
            break;
    }
    switch (self.viewItem.attachmentPointer.pointerType) {
        case TSAttachmentPointerTypeRestoring:
            // TODO: Show "restoring" indicator and possibly progress.
            return;
        case TSAttachmentPointerTypeUnknown:
        case TSAttachmentPointerTypeIncoming:
            break;
    }
    NSString *_Nullable uniqueId = self.viewItem.attachmentPointer.uniqueId;
    if (uniqueId.length < 1) {
        OWSFailDebug(@"Missing uniqueId.");
        return;
    }

    CGFloat downloadViewSize = self.iconSize;
    MediaDownloadView *downloadView =
        [[MediaDownloadView alloc] initWithAttachmentId:uniqueId radius:downloadViewSize * 0.5f];
    iconView.layer.opacity = 0.01f;
    [self addSubview:downloadView];
    [downloadView autoSetDimensionsToSize:CGSizeMake(downloadViewSize, downloadViewSize)];
    [downloadView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:iconView];
    [downloadView autoAlignAxis:ALAxisVertical toSameAxisOfView:iconView];
}

#pragma mark -

- (CGFloat)hMargin
{
    return 0.f;
}

- (CGFloat)hSpacing
{
    return 12.f;
}

+ (CGFloat)vMargin
{
    return 4.f;
}

- (CGFloat)vMargin
{
    return [OWSAudioMessageView vMargin];
}

+ (CGFloat)bubbleHeight
{
    CGFloat contentHeight = ([OWSAudioMessageView labelFont].lineHeight + [OWSAudioMessageView waveformMaxHeight] +
        [OWSAudioMessageView vSpacing]);
    return contentHeight + self.vMargin * 2;
}

- (CGFloat)bubbleHeight
{
    return [OWSAudioMessageView bubbleHeight];
}

+ (CGFloat)iconSize
{
    return 24;
}

- (CGFloat)iconSize
{
    return [OWSAudioMessageView iconSize];
}

- (BOOL)isVoiceMessage
{
    return self.attachment.isVoiceMessage;
}

- (void)createContents
{
    self.axis = UILayoutConstraintAxisVertical;
    self.spacing = [OWSAudioMessageView vSpacing];

    NSString *_Nullable filename = self.attachment.sourceFilename;
    if (filename.length < 1) {
        filename = [self.attachmentStream.originalFilePath lastPathComponent];
    }
    NSString *topText = [[filename stringByDeletingPathExtension] ows_stripped];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType].localizedUppercaseString;
    }
    if (topText.length < 1) {
        topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
    }
    if (self.isVoiceMessage) {
        topText = nil;
    }
    UILabel *topLabel = [UILabel new];
    topLabel.text = topText;
    topLabel.textColor = [self.conversationStyle bubbleTextColorWithIsIncoming:self.isIncoming];
    topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    topLabel.font = [OWSAudioMessageView labelFont];
    [self addArrangedSubview:topLabel];
    topLabel.hidden = topText == nil;

    _audioPlayPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.audioPlayPauseButton.enabled = NO;
    [self.audioPlayPauseButton setContentHuggingHigh];

    UIView *waveformContainer = [UIView containerView];
    [waveformContainer autoSetDimension:ALDimensionHeight toSize:[OWSAudioMessageView waveformMaxHeight]];

    AudioWaveformProgressView *waveformProgressView = [AudioWaveformProgressView new];
    self.waveformProgressView = waveformProgressView;
    [waveformContainer addSubview:waveformProgressView];
    [waveformProgressView autoPinEdgesToSuperviewEdges];

    UISlider *audioProgressSlider = [UISlider new];
    self.audioProgressSlider = audioProgressSlider;
    [waveformContainer addSubview:audioProgressSlider];
    [audioProgressSlider autoPinWidthToSuperview];
    [audioProgressSlider autoSetDimension:ALDimensionHeight toSize:12];
    [audioProgressSlider autoVCenterInSuperview];

    [self updateWaveformProgressView];

    UILabel *playbackTimeLabel = [UILabel new];
    self.playbackTimeLabel = playbackTimeLabel;
    [self updateAudioBottomLabel:self.audioProgressSeconds];
    playbackTimeLabel.textColor = [self.conversationStyle bubbleSecondaryTextColorWithIsIncoming:self.isIncoming];
    playbackTimeLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    playbackTimeLabel.font = [OWSAudioMessageView progressLabelFont];
    [playbackTimeLabel setContentHuggingHigh];

    UIStackView *playerStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.audioPlayPauseButton, waveformContainer, playbackTimeLabel ]];
    playerStack.layoutMarginsRelativeArrangement = YES;
    playerStack.layoutMargins = UIEdgeInsetsMake(self.vMargin, self.hMargin, self.vMargin, self.hMargin);
    playerStack.axis = UILayoutConstraintAxisHorizontal;
    playerStack.spacing = self.hSpacing;

    [self addArrangedSubview:playerStack];

    [waveformContainer autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.audioPlayPauseButton];

    [self replaceIconWithDownloadProgressIfNecessary:self.audioPlayPauseButton];

    [self updateContents];
}

+ (CGFloat)waveformMaxHeight
{
    return 35.f;
}

+ (UIFont *)labelFont
{
    return [UIFont ows_dynamicTypeCaption2Font];
}

+ (UIFont *)progressLabelFont
{
    return [[UIFont ows_dynamicTypeCaption1Font] ows_monospaced];
}

+ (CGFloat)vSpacing
{
    return 2.f;
}

- (BOOL)isPointInScrubbableRegion:(CGPoint)location
{
    CGPoint locationInSlider = [self convertPoint:location toView:self.waveformProgressView];
    return locationInSlider.x >= 0 && locationInSlider.x <= self.waveformProgressView.width;
}

- (NSTimeInterval)scrubToLocation:(CGPoint)location
{
    CGRect sliderContainer = [self convertRect:self.waveformProgressView.frame
                                      fromView:self.waveformProgressView.superview];

    CGFloat newRatio = CGFloatClamp01(CGFloatInverseLerp(location.x, CGRectGetMinX(sliderContainer), CGRectGetMaxX(sliderContainer)));

    // When in RTL mode, the slider moves in the opposite direction so inverse the ratio.
    if (CurrentAppContext().isRTL) {
        newRatio = 1 - newRatio;
    }

    [self setProgressRatio:newRatio];

    CGFloat newProgressSeconds = newRatio * self.audioDurationSeconds;

    [self updateAudioBottomLabel:newProgressSeconds];

    return newProgressSeconds;
}

@end

NS_ASSUME_NONNULL_END
