//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

@property (nonatomic) TSAttachmentStream *attachmentStream;
@property (nonatomic) BOOL isIncoming;
@property (nonatomic, weak) ConversationViewItem *viewItem;

@property (nonatomic, nullable) UIButton *audioPlayPauseButton;
@property (nonatomic, nullable) UILabel *audioBottomLabel;
@property (nonatomic, nullable) AudioProgressView *audioProgressView;

@end

#pragma mark -

@implementation OWSAudioMessageView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream
                        isIncoming:(BOOL)isIncoming
                          viewItem:(ConversationViewItem *)viewItem
{
    self = [super init];

    if (self) {
        _attachmentStream = attachmentStream;
        _isIncoming = isIncoming;
        _viewItem = viewItem;
    }

    return self;
}

- (void)updateContents
{
    [self updateAudioProgressView];
    [self updateAudioBottomLabel];

    if (self.audioPlaybackState == AudioPlaybackState_Playing) {
        [self setAudioIconToPause];
    } else {
        [self setAudioIconToPlay];
    }
}

- (CGFloat)audioProgressSeconds
{
    return [self.viewItem audioProgressSeconds];
}

- (CGFloat)audioDurationSeconds
{
    OWSAssert(self.viewItem.audioDurationSeconds > 0.f);

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

- (void)updateAudioBottomLabel
{
    if (self.isAudioPlaying && self.audioProgressSeconds > 0 && self.audioDurationSeconds > 0) {
        self.audioBottomLabel.text =
            [NSString stringWithFormat:@"%@ / %@",
                      [OWSFormat formatDurationSeconds:(long)round(self.audioProgressSeconds)],
                      [OWSFormat formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    } else {
        self.audioBottomLabel.text =
            [NSString stringWithFormat:@"%@", [OWSFormat formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    }
}

- (void)setAudioIcon:(UIImage *)icon iconColor:(UIColor *)iconColor
{
    OWSAssert(icon.size.height == self.iconSize);

    icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateNormal];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateDisabled];
    _audioPlayPauseButton.imageView.tintColor = self.bubbleBackgroundColor;
    _audioPlayPauseButton.backgroundColor = iconColor;
    _audioPlayPauseButton.layer.cornerRadius = self.iconSize * 0.5f;
}

- (void)setAudioIconToPlay
{
    [self setAudioIcon:[UIImage imageNamed:@"audio_play_black_40"]
             iconColor:(self.isIncoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self audioColorWithOpacity:0.15f])];
}

- (void)setAudioIconToPause
{
    [self setAudioIcon:[UIImage imageNamed:@"audio_pause_black_40"]
             iconColor:(self.isIncoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self audioColorWithOpacity:0.15f])];
}

- (void)updateAudioProgressView
{
    [self.audioProgressView
        setProgress:(self.audioDurationSeconds > 0 ? self.audioProgressSeconds / self.audioDurationSeconds : 0.f)];

    self.audioProgressView.horizontalBarColor = [self audioColorWithOpacity:0.75f];
    self.audioProgressView.progressColor
        = (self.isAudioPlaying ? [self audioColorWithOpacity:self.isIncoming ? 0.2f : 0.1f]
                               : [self audioColorWithOpacity:0.4f]);
}

#pragma mark -

- (CGFloat)hMargin
{
    return 0.f;
}

- (CGFloat)hSpacing
{
    return 8.f;
}

+ (CGFloat)vMargin
{
    return 0.f;
}

- (CGFloat)vMargin
{
    return [OWSAudioMessageView vMargin];
}

+ (CGFloat)bubbleHeight
{
    CGFloat iconHeight = self.iconSize;
    CGFloat labelsHeight = ([OWSAudioMessageView labelFont].lineHeight * 2 +
        [OWSAudioMessageView audioProgressViewHeight] + [OWSAudioMessageView labelVSpacing] * 2);
    CGFloat contentHeight = MAX(iconHeight, labelsHeight);
    return contentHeight + self.vMargin * 2;
}

- (CGFloat)bubbleHeight
{
    return [OWSAudioMessageView bubbleHeight];
}

+ (CGFloat)iconSize
{
    return 40.f;
}

- (CGFloat)iconSize
{
    return [OWSAudioMessageView iconSize];
}

- (UIColor *)audioTextColor
{
    return (self.isIncoming ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor whiteColor]);
}

- (UIColor *)audioColorWithOpacity:(CGFloat)alpha
{
    return [self.audioTextColor blendWithColor:self.bubbleBackgroundColor alpha:alpha];
}

- (UIColor *)bubbleBackgroundColor
{
    return self.isIncoming ? [UIColor ows_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
}

- (BOOL)isVoiceMessage
{
    // We want to treat "pre-voice messages flag" messages as voice messages if
    // they have no file name.
    //
    // TODO: Remove this after the flag has been in production for a few months.
    return (self.attachmentStream.isVoiceMessage || self.attachmentStream.sourceFilename.length < 1);
}

- (void)createContents
{
    UIColor *textColor = [self audioTextColor];

    self.axis = UILayoutConstraintAxisHorizontal;
    self.alignment = UIStackViewAlignmentCenter;
    self.spacing = self.hSpacing;

    _audioPlayPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.audioPlayPauseButton.enabled = NO;
    [self addArrangedSubview:self.audioPlayPauseButton];
    [self.audioPlayPauseButton setContentHuggingHigh];

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = [OWSAudioMessageView labelVSpacing];
    [self addArrangedSubview:labelsView];

    NSString *filename = self.attachmentStream.sourceFilename;
    if (!filename) {
        filename = [[self.attachmentStream filePath] lastPathComponent];
    }
    NSString *topText = [[filename stringByDeletingPathExtension] ows_stripped];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachmentStream.contentType].uppercaseString;
    }
    if (topText.length < 1) {
        topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
    }
    if (self.isVoiceMessage) {
        topText = nil;
    }
    UILabel *topLabel = [UILabel new];
    topLabel.text = topText;
    topLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    topLabel.font = [OWSAudioMessageView labelFont];
    [labelsView addArrangedSubview:topLabel];

    AudioProgressView *audioProgressView = [AudioProgressView new];
    self.audioProgressView = audioProgressView;
    [self updateAudioProgressView];
    [labelsView addArrangedSubview:audioProgressView];
    [audioProgressView autoSetDimension:ALDimensionHeight toSize:[OWSAudioMessageView audioProgressViewHeight]];

    UILabel *bottomLabel = [UILabel new];
    self.audioBottomLabel = bottomLabel;
    [self updateAudioBottomLabel];
    bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [OWSAudioMessageView labelFont];
    [labelsView addArrangedSubview:bottomLabel];

    [self updateContents];
}

+ (CGFloat)audioProgressViewHeight
{
    return 12.f;
}

+ (UIFont *)labelFont
{
    return [UIFont ows_dynamicTypeCaption2Font];
}

+ (CGFloat)labelVSpacing
{
    return 2.f;
}

@end

NS_ASSUME_NONNULL_END
