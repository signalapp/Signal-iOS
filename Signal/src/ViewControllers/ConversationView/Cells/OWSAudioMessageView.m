//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioMessageView.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "ViewControllerUtils.h"
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
    NSNumber *_Nullable audioDurationSeconds = self.viewItem.audioDurationSeconds;
    if (!audioDurationSeconds) {
        audioDurationSeconds = @([self.attachmentStream audioDurationSecondsWithoutTransaction]);
        self.viewItem.audioDurationSeconds = audioDurationSeconds;
    }
    return [audioDurationSeconds floatValue];
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
                      [ViewControllerUtils formatDurationSeconds:(long)round(self.audioProgressSeconds)],
                      [ViewControllerUtils formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    } else {
        self.audioBottomLabel.text = [NSString
            stringWithFormat:@"%@", [ViewControllerUtils formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    }
}

- (void)setAudioIcon:(UIImage *)icon iconColor:(UIColor *)iconColor
{
    icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateNormal];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateDisabled];
    _audioPlayPauseButton.imageView.tintColor = self.bubbleBackgroundColor;
    _audioPlayPauseButton.backgroundColor = iconColor;
    _audioPlayPauseButton.layer.cornerRadius
        = MIN(_audioPlayPauseButton.bounds.size.width, _audioPlayPauseButton.bounds.size.height) * 0.5f;
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

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)audioIconHMargin
{
    return 12.f;
}

- (CGFloat)audioIconHSpacing
{
    return 10.f;
}

+ (CGFloat)audioIconVMargin
{
    return 12.f;
}

- (CGFloat)audioIconVMargin
{
    return [OWSAudioMessageView audioIconVMargin];
}

+ (CGFloat)bubbleHeight
{
    return self.iconSize + self.audioIconVMargin * 2;
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
    return self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
}

- (BOOL)isVoiceMessage
{
    // We want to treat "pre-voice messages flag" messages as voice messages if
    // they have no file name.
    //
    // TODO: Remove this after the flag has been in production for a few months.
    return (self.attachmentStream.isVoiceMessage || self.attachmentStream.sourceFilename.length < 1);
}

- (void)createContentsForSize:(CGSize)viewSize
{
    UIColor *textColor = [self audioTextColor];

    self.backgroundColor = self.bubbleBackgroundColor;

    const CGFloat kBubbleTailWidth = 6.f;
    CGRect contentFrame = CGRectMake(self.isIncoming ? kBubbleTailWidth : 0.f,
        self.audioIconVMargin,
        viewSize.width - kBubbleTailWidth - self.audioIconHMargin,
        viewSize.height - self.audioIconVMargin * 2);

    CGRect iconFrame = CGRectMake((CGFloat)round(contentFrame.origin.x + self.audioIconHMargin),
        (CGFloat)round(contentFrame.origin.y + (contentFrame.size.height - self.iconSize) * 0.5f),
        self.iconSize,
        self.iconSize);
    _audioPlayPauseButton = [[UIButton alloc] initWithFrame:iconFrame];
    _audioPlayPauseButton.enabled = NO;
    [self addSubview:_audioPlayPauseButton];

    const CGFloat kLabelHSpacing = self.audioIconHSpacing;
    const CGFloat kLabelVSpacing = 2;
    NSString *filename = self.attachmentStream.sourceFilename;
    if (!filename) {
        filename = [[self.attachmentStream filePath] lastPathComponent];
    }
    NSString *topText = [[filename stringByDeletingPathExtension]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
    topLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
    [topLabel sizeToFit];
    [self addSubview:topLabel];

    AudioProgressView *audioProgressView = [AudioProgressView new];
    self.audioProgressView = audioProgressView;
    [self updateAudioProgressView];
    [self addSubview:audioProgressView];

    UILabel *bottomLabel = [UILabel new];
    self.audioBottomLabel = bottomLabel;
    [self updateAudioBottomLabel];
    bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
    [bottomLabel sizeToFit];
    [self addSubview:bottomLabel];

    const CGFloat topLabelHeight = (CGFloat)ceil(topLabel.font.lineHeight);
    const CGFloat kAudioProgressViewHeight = 12.f;
    const CGFloat bottomLabelHeight = (CGFloat)ceil(bottomLabel.font.lineHeight);
    CGRect labelsBounds = CGRectZero;
    labelsBounds.origin.x = (CGFloat)round(iconFrame.origin.x + iconFrame.size.width + kLabelHSpacing);
    labelsBounds.size.width = contentFrame.origin.x + contentFrame.size.width - labelsBounds.origin.x;
    labelsBounds.size.height = topLabelHeight + kAudioProgressViewHeight + bottomLabelHeight + kLabelVSpacing * 2;
    labelsBounds.origin.y
        = (CGFloat)round(contentFrame.origin.y + (contentFrame.size.height - labelsBounds.size.height) * 0.5f);

    CGFloat y = labelsBounds.origin.y;
    topLabel.frame = CGRectMake(labelsBounds.origin.x, labelsBounds.origin.y, labelsBounds.size.width, topLabelHeight);
    y += topLabelHeight + kLabelVSpacing;
    audioProgressView.frame = CGRectMake(labelsBounds.origin.x, y, labelsBounds.size.width, kAudioProgressViewHeight);
    y += kAudioProgressViewHeight + kLabelVSpacing;
    bottomLabel.frame = CGRectMake(labelsBounds.origin.x, y, labelsBounds.size.width, bottomLabelHeight);

    [self updateContents];
}

@end

NS_ASSUME_NONNULL_END
