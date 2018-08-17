//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSearchBar;

@protocol OWSSearchBarDelegate <NSObject>

- (void)searchBar:(OWSSearchBar *)searchBar textDidChange:(NSString *)text;
- (void)searchBar:(OWSSearchBar *)searchBar returnWasPressed:(NSString *)text;

@optional
- (void)searchBarDidBeginEditing:(OWSSearchBar *)searchBar;

@end

#pragma mark -

@interface OWSSearchBar : UIView

@property (nonatomic, weak) id<OWSSearchBarDelegate> delegate;

@property (nonatomic, nullable) NSString *text;

@property (nonatomic, nullable) NSString *placeholder;

@end

NS_ASSUME_NONNULL_END
