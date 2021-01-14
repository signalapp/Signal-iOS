//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class GalleryItemBox;
@class MediaDetailViewController;
@class TSAttachment;

typedef NS_OPTIONS(NSInteger, MediaGalleryOption) {
    MediaGalleryOptionSliderEnabled = 1 << 0,
    MediaGalleryOptionShowAllMediaButton = 1 << 1
};

@protocol MediaDetailViewControllerDelegate <NSObject>

- (void)mediaDetailViewController:(MediaDetailViewController *)mediaDetailViewController
                   isPlayingVideo:(BOOL)isPlayingVideo;

- (void)mediaDetailViewControllerDidTapMedia:(MediaDetailViewController *)mediaDetailViewController;

@end

@interface MediaDetailViewController : OWSViewController

@property (nonatomic, readonly) UIView *mediaView;
@property (nonatomic, weak) id<MediaDetailViewControllerDelegate> delegate;
@property (nonatomic, readonly) GalleryItemBox *galleryItemBox;

// If viewItem is non-null, long press will show a menu controller.
- (instancetype)initWithGalleryItemBox:(GalleryItemBox *)galleryItemBox shouldAutoPlayVideo:(BOOL)shouldAutoPlayVideo;

#pragma mark - Actions

- (void)didPressPlayBarButton:(id)sender;
- (void)didPressPauseBarButton:(id)sender;
- (void)playVideo;

// Stops playback and rewinds
- (void)stopAnyVideo;

- (void)setShouldHideToolbars:(BOOL)shouldHideToolbars;
- (void)zoomOutAnimated:(BOOL)isAnimated;

@end

NS_ASSUME_NONNULL_END
