//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class GalleryItemBox;
@class MediaDetailViewController;

@protocol MediaDetailViewControllerDelegate <NSObject>

- (void)dismissSelfAnimated:(BOOL)isAnimated completion:(void (^_Nullable)(void))completionBlock;
- (void)mediaDetailViewController:(MediaDetailViewController *)mediaDetailViewController
                   isPlayingVideo:(BOOL)isPlayingVideo;

@end

@interface MediaDetailViewController : OWSViewController

@property (nonatomic, weak) id<MediaDetailViewControllerDelegate> delegate;
@property (nonatomic, readonly) GalleryItemBox *galleryItemBox;

// If viewItem is non-null, long press will show a menu controller.
- (instancetype)initWithGalleryItemBox:(GalleryItemBox *)galleryItemBox
                              viewItem:(ConversationViewItem *_Nullable)viewItem;
#pragma mark - Actions

- (void)didPressShare:(id)sender;
- (void)didPressDelete:(id)sender;
- (void)didPressPlayBarButton:(id)sender;
- (void)didPressPauseBarButton:(id)sender;
- (void)playVideo;

// Stops playback and rewinds
- (void)stopAnyVideo;

- (void)setShouldHideToolbars:(BOOL)shouldHideToolbars;
- (void)zoomOutAnimated:(BOOL)isAnimated;

@end

NS_ASSUME_NONNULL_END
