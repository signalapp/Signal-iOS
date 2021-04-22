//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class GiphyDownloader: ProxiedContentDownloader {

    // MARK: - Properties

    @objc
    public static let giphyDownloader = GiphyDownloader(downloadFolderName: "GIFs")
}
