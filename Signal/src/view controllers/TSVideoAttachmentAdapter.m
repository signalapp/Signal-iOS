//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"
#import "TSMessagesManager.h"

#import "UIDevice+TSHardwareVersion.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"
#import "FFCircularProgressView.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSNetworkManager.h"

@interface TSVideoAttachmentAdapter ()

@property UIImage *image;

@property (strong, nonatomic) UIImageView *cachedImageView;
@property (strong, nonatomic) UIImageView *playButton;
@property (strong, nonatomic) CALayer *maskLayer;
@property (strong, nonatomic) FFCircularProgressView *progressView;
@property (strong, nonatomic) TSAttachmentStream *attachment;
@property (strong, nonatomic) NSString *videoURL;
@end

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment{
    self = [super initWithFileURL:[attachment videoURL] isReadyToPlay:YES];
    
    if (self) {
        NSLog(@"attach: %@", attachment);
        _image           = attachment.image;
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        _attachment = attachment;
        
    }
    return self;
}

-(BOOL) isImage{
    return NO;
}

-(BOOL) isAudio {
    return [_contentType containsString:@"audio/"];
}


-(BOOL) isVideo {
    return [_contentType containsString:@"video/"];
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView
{
    if (self.image == nil) {
        return nil;
    }
    
    if (self.cachedImageView == nil) {
        CGSize size = [self mediaViewDisplaySize];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
        imageView.frame = CGRectMake(0.0f, 0.0f, size.width, size.height);
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView isOutgoing:self.appliesMediaViewMaskAsOutgoing];
        self.cachedImageView = imageView;
        UIImage *img = [UIImage imageNamed:@"play_button"]; 
        _playButton = [[UIImageView alloc] initWithImage:img];
        _playButton.frame = CGRectMake((size.width/2)-18, (size.height/2)-18, 37, 37);
        [self.cachedImageView addSubview:_playButton];
        _playButton.hidden = YES;
        _maskLayer = [CALayer layer];
        [_maskLayer setBackgroundColor:[UIColor blackColor].CGColor];
        [_maskLayer setOpacity:0.4f];
        [_maskLayer setFrame:self.cachedImageView.frame];
        [self.cachedImageView.layer addSublayer:_maskLayer];
        _progressView = [[FFCircularProgressView alloc] initWithFrame:CGRectMake((size.width/2)-18, (size.height/2)-18, 37, 37)];
        [_cachedImageView addSubview:_progressView];
        if (_attachment.isDownloaded) {
            _playButton.hidden = NO;
            _maskLayer.hidden = YES;
            _progressView.hidden = YES;
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachmentUploadProgress:) name:@"attachmentUploadProgress" object:nil];
        
    }
    
    return self.cachedImageView;
}

- (void)attachmentUploadProgress:(NSNotification*)notification {
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:@"progress"] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:@"attachmentID"];
    if ([_attachmentId isEqualToString:attachmentID]) {
        NSLog(@"is downloaded: %d", _attachment.isDownloaded);
        [_progressView setProgress:progress];
        if (progress >= 1) {
            _maskLayer.hidden = YES;
            _progressView.hidden = YES;
            _playButton.hidden = NO;
            _attachment.isDownloaded = YES;
            [[TSMessagesManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [_attachment saveWithTransaction:transaction];
            }];
        }
    }
    //set progress on bar
}

- (void)dealloc {
    _image = nil;
    _cachedImageView = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

@end
