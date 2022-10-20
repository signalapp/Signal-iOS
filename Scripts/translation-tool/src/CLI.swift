//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum Constant {
    static let concurrentRequestLimit = 12
    static let projectIdentifier = "4b899d72e"
    static let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

@main
struct CLI {

    // MARK: - Entrypoint

    static func main() async throws {
        var remainingArgs = CommandLine.arguments.dropFirst()
        while let arg = remainingArgs.popFirst() {
            switch arg {
            case "upload-metadata":
                try await loadCLI().uploadFiles(metadataFiles)
            case "upload-resources":
                try await loadCLI().uploadFiles(resourceFiles)
            case "download-metadata":
                try MetadataFile.checkForUnusedLocalizations(in: Constant.repositoryURL)
                try await loadCLI().downloadFiles(metadataFiles)
            case "download-resources":
                try ResourceFile.checkForUnusedLocalizations(in: Constant.repositoryURL)
                try await loadCLI().downloadFiles(resourceFiles)
            case "genstrings-pluralaware":
                guard let temporaryDirectoryPath = remainingArgs.popFirst() else {
                    print("Missing temporary directory path")
                    exit(1)
                }
                try Genstrings.filterPluralAware(
                    resourceFile: pluralAwareFile,
                    repositoryURL: Constant.repositoryURL,
                    temporaryDirectoryURL: URL(fileURLWithPath: temporaryDirectoryPath)
                )
            default:
                print("Unknown action: \(arg)")
            }
        }
    }

    private static var loadedCLI: CLI?
    static func loadCLI() throws -> CLI {
        if let result = loadedCLI {
            return result
        }
        guard let (userIdentifier, userSecret) = try loadUserParameters() else {
            showIntructionsForUserParameters()
        }
        let client = Smartling(
            projectIdentifier: Constant.projectIdentifier,
            userIdentifier: userIdentifier,
            userSecret: userSecret
        )
        let result = CLI(repositoryURL: Constant.repositoryURL, client: client)
        loadedCLI = result
        return result
    }

    // MARK: - Upload & Download

    private static let metadataFiles: [MetadataFile] = [
        MetadataFile(filename: "release_notes.txt"),
        MetadataFile(filename: "description.txt")
    ]

    private static let pluralAwareFile = ResourceFile(filename: "PluralAware.stringsdict")

    private static let resourceFiles: [ResourceFile] = [
        ResourceFile(filename: "InfoPlist.strings"),
        ResourceFile(filename: "Localizable.strings"),
        pluralAwareFile
    ]

    var repositoryURL: URL
    var client: Smartling

    private func uploadFiles(_ files: [TranslatableFile]) async throws {
        try await withLimitedThrowingTaskGroup(limit: Constant.concurrentRequestLimit) { taskGroup in
            for translatableFile in files {
                try await taskGroup.addTask {
                    try await client.uploadSourceFile(
                        at: repositoryURL.appendingPathComponent(translatableFile.relativeSourcePath)
                    )
                    print("Uploaded \(translatableFile.filename)")
                }
            }
        }
    }

    private func downloadFiles(_ files: [TranslatableFile]) async throws {
        // Each of these kicks off a bunch of downloads in parallel, so it's fine to do these serially.
        for translatableFile in files {
            try await translatableFile.downloadAllTranslations(to: repositoryURL, using: client)
        }
    }

    // MARK: - Config

    private static func loadUserParameters() throws -> (String, String)? {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".smartling/auth")
        let fileContent: String
        do {
            fileContent = try String(contentsOf: fileURL).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let components = fileContent.split(separator: "\n")
        guard components.count == 2 else {
            return nil
        }
        return (String(components[0]), String(components[1]))
    }

    private static func showIntructionsForUserParameters() -> Never {
        print("")
        print("Couldn't load user identifier/user secret from ~/.smartling/auth.")
        print("")
        print("That file should contain two lines: (1) user identifier & (2) user secret.")
        print("You can create a token using Smartling's web interface.")
        print("")
        exit(1)
    }
}
