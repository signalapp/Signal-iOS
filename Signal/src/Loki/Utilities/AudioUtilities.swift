import Accelerate
import PromiseKit

enum AudioUtilities {
    private static let noiseFloor: Float = -80

    private struct FileInfo {
        let url: URL
        let sampleCount: Int
        let asset: AVAsset
        let track: AVAssetTrack
    }

    enum Error : LocalizedError {
        case noAudioTrack
        case noAudioFormatDescription
        case loadingFailed
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "No audio track."
            case .noAudioFormatDescription: return "No audio format description."
            case .loadingFailed: return "Couldn't load asset."
            case .parsingFailed: return "Couldn't parse asset."
            }
        }
    }

    static func getVolumeSamples(for audioFileURL: URL, targetSampleCount: Int = 32) -> Promise<(duration: Double, volumeSamples: [Float])> {
        return loadFile(audioFileURL).then { fileInfo in
            AudioUtilities.parseSamples(from: fileInfo, with: targetSampleCount)
        }
    }

    private static func loadFile(_ audioFileURL: URL) -> Promise<FileInfo> {
        let asset = AVURLAsset(url: audioFileURL)
        guard let track = asset.tracks(withMediaType: AVMediaType.audio).first else {
            return Promise(error: Error.noAudioTrack)
        }
        let (promise, seal) = Promise<FileInfo>.pending()
        asset.loadValuesAsynchronously(forKeys: [ "duration" ]) {
            var nsError: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &nsError)
            switch status {
            case .loaded:
                guard let formatDescriptions = track.formatDescriptions as? [CMAudioFormatDescription],
                    let audioFormatDescription = formatDescriptions.first,
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription)
                    else { return seal.reject(Error.noAudioFormatDescription) }
                let sampleCount = Int((asbd.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale))
                let fileInfo = FileInfo(url: audioFileURL, sampleCount: sampleCount, asset: asset, track: track)
                seal.fulfill(fileInfo)
            default:
                print("Couldn't load asset due to error: \(nsError?.localizedDescription ?? "no description provided").")
                seal.reject(Error.loadingFailed)
            }
        }
        return promise
    }

    private static func parseSamples(from fileInfo: FileInfo, with targetSampleCount: Int) -> Promise<(duration: Double, volumeSamples: [Float])> {
        // Prepare the reader
        guard let reader = try? AVAssetReader(asset: fileInfo.asset) else { return Promise(error: Error.parsingFailed) }
        let range = 0..<fileInfo.sampleCount
        reader.timeRange = CMTimeRange(start: CMTime(value: Int64(range.lowerBound), timescale: fileInfo.asset.duration.timescale),
            duration: CMTime(value: Int64(range.count), timescale: fileInfo.asset.duration.timescale))
        let outputSettings: [String:Any] = [
            AVFormatIDKey : Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey : 16,
            AVLinearPCMIsBigEndianKey : false,
            AVLinearPCMIsFloatKey : false,
            AVLinearPCMIsNonInterleaved : false
        ]
        let output = AVAssetReaderTrackOutput(track: fileInfo.track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        var channelCount = 1
        let formatDescriptions = fileInfo.track.formatDescriptions as! [CMAudioFormatDescription]
        for audioFormatDescription in formatDescriptions {
            guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription) else {
                return Promise(error: Error.parsingFailed)
            }
            channelCount = Int(asbd.pointee.mChannelsPerFrame)
        }
        let samplesPerPixel = max(1, channelCount * range.count / targetSampleCount)
        let filter = [Float](repeating: 1 / Float(samplesPerPixel), count: samplesPerPixel)
        var result = [Float]()
        var sampleBuffer = Data()
        // Read the file
        reader.startReading()
        defer { reader.cancelReading() }
        while reader.status == .reading {
            guard let readSampleBuffer = output.copyNextSampleBuffer(),
                let readBuffer = CMSampleBufferGetDataBuffer(readSampleBuffer) else { break }
            var readBufferLength = 0
            var readBufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(readBuffer,
                                        atOffset: 0,
                                        lengthAtOffsetOut: &readBufferLength,
                                        totalLengthOut: nil,
                                        dataPointerOut: &readBufferPointer)
            sampleBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
            CMSampleBufferInvalidate(readSampleBuffer)
            let sampleCount = sampleBuffer.count / MemoryLayout<Int16>.size
            let downSampledLength = sampleCount / samplesPerPixel
            let samplesToProcess = downSampledLength * samplesPerPixel
            guard samplesToProcess > 0 else { continue }
            processSamples(from: &sampleBuffer,
                           outputSamples: &result,
                           samplesToProcess: samplesToProcess,
                           downSampledLength: downSampledLength,
                           samplesPerPixel: samplesPerPixel,
                           filter: filter)
        }
        // Process any remaining samples
        let samplesToProcess = sampleBuffer.count / MemoryLayout<Int16>.size
        if samplesToProcess > 0 {
            let downSampledLength = 1
            let samplesPerPixel = samplesToProcess
            let filter = [Float](repeating: 1.0 / Float(samplesPerPixel), count: samplesPerPixel)
            processSamples(from: &sampleBuffer,
                           outputSamples: &result,
                           samplesToProcess: samplesToProcess,
                           downSampledLength: downSampledLength,
                           samplesPerPixel: samplesPerPixel,
                           filter: filter)
        }
        guard reader.status == .completed else { return Promise(error: Error.parsingFailed) }
        // Return
        let duration = fileInfo.asset.duration.seconds
        return Promise { $0.fulfill((duration, result)) }
    }

    private static func processSamples(from sampleBuffer: inout Data, outputSamples: inout [Float], samplesToProcess: Int,
        downSampledLength: Int, samplesPerPixel: Int, filter: [Float]) {
        sampleBuffer.withUnsafeBytes { (samples: UnsafeRawBufferPointer) in
            var processingBuffer = [Float](repeating: 0, count: samplesToProcess)
            let sampleCount = vDSP_Length(samplesToProcess)
            // Create an UnsafePointer<Int16> from the samples
            let unsafeBufferPointer = samples.bindMemory(to: Int16.self)
            let unsafePointer = unsafeBufferPointer.baseAddress!
            // Convert 16 bit int samples to floats
            vDSP_vflt16(unsafePointer, 1, &processingBuffer, 1, sampleCount)
            // Take the absolute values to get the amplitude
            vDSP_vabs(processingBuffer, 1, &processingBuffer, 1, sampleCount)
            // Get the corresponding dB values and clip the results
            getdB(from: &processingBuffer)
            // Downsample and average
            var downSampledData = [Float](repeating: 0, count: downSampledLength)
            vDSP_desamp(processingBuffer,
                        vDSP_Stride(samplesPerPixel),
                        filter,
                        &downSampledData,
                        vDSP_Length(downSampledLength),
                        vDSP_Length(samplesPerPixel))
            // Remove the processed samples
            sampleBuffer.removeFirst(samplesToProcess * MemoryLayout<Int16>.size)
            // Update the output samples
            outputSamples += downSampledData
        }
    }

    static func getdB(from normalizedSamples: inout [Float]) {
        // Convert samples to a log scale
        var zero: Float = 32768.0
        vDSP_vdbcon(normalizedSamples, 1, &zero, &normalizedSamples, 1, vDSP_Length(normalizedSamples.count), 1)
        // Clip to [noiseFloor, 0]
        var ceil: Float = 0.0
        var noiseFloorMutable = AudioUtilities.noiseFloor
        vDSP_vclip(normalizedSamples, 1, &noiseFloorMutable, &ceil, &normalizedSamples, 1, vDSP_Length(normalizedSamples.count))
    }
}
