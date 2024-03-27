//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class GiphyDownloader: ProxiedContentDownloader {

    // MARK: - Properties

    @objc
    public static let giphyDownloader = GiphyDownloader(downloadFolderName: "GIFs")
}
