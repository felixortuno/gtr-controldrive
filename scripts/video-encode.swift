import Foundation
import AVFoundation
import AppKit
import CoreVideo

struct Narration: Decodable { let file: String; let start: Double; let duration: Double }
struct Manifest: Decodable { let fps: Int32; let width: Int; let height: Int; let duration: Double; let frames: [String]; let audio: [Narration]; let output: String }
let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
let silentURL = manifestURL.deletingLastPathComponent().appendingPathComponent("silent.mp4")
let outputURL = URL(fileURLWithPath: manifest.output)
try? FileManager.default.removeItem(at: silentURL)
try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: manifest.width, AVVideoHeightKey: manifest.height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1100000, AVVideoExpectedSourceFrameRateKey: manifest.fps, AVVideoMaxKeyFrameIntervalKey: manifest.fps * 2, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: manifest.width, kCVPixelBufferHeightKey as String: manifest.height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for (i, path) in manifest.frames.enumerated() {
  while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
  try autoreleasepool {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw NSError(domain: "Video", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(path)"]) }
    var optionalBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &optionalBuffer) == kCVReturnSuccess, let buffer = optionalBuffer else { throw NSError(domain: "Video", code: 2) }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: manifest.width, height: manifest.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: manifest.width, height: manifest.height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: manifest.fps)) else { throw writer.error ?? NSError(domain: "Video", code: 3) }
  }
  if i % 100 == 0 { print("Encoded \(i)/\(manifest.frames.count) frames") }
}
input.markAsFinished()
writer.endSession(atSourceTime: CMTime(seconds: manifest.duration, preferredTimescale: 600))
let finish = DispatchSemaphore(value: 0)
writer.finishWriting { finish.signal() }
finish.wait()
if writer.status != .completed { throw writer.error ?? NSError(domain: "Video", code: 4) }

let composition = AVMutableComposition()
let videoAsset = AVURLAsset(url: silentURL)
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
if !manifest.audio.isEmpty {
let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
for narration in manifest.audio {
  let asset = AVURLAsset(url: URL(fileURLWithPath: narration.file))
  try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .audio)[0], at: CMTime(seconds: narration.start, preferredTimescale: 600))
}
}
// Without narration the H.264 track is copied as is (no second compression); with narration, HighestQuality converts the voice to AAC.
let exporter = AVAssetExportSession(asset: composition, presetName: manifest.audio.isEmpty ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality)!
exporter.outputURL = outputURL
exporter.outputFileType = .mp4
exporter.shouldOptimizeForNetworkUse = true
let exported = DispatchSemaphore(value: 0)
exporter.exportAsynchronously { exported.signal() }
exported.wait()
if exporter.status != .completed { throw exporter.error ?? NSError(domain: "Video", code: 5) }
let finished = AVURLAsset(url: outputURL)
print("MP4 ready: \(finished.duration.seconds)s, \(finished.tracks(withMediaType: .video).count) video track, \(finished.tracks(withMediaType: .audio).count) audio track")
