import CoreGraphics
import Foundation
import ImageIO
import TackCore
import UniformTypeIdentifiers
import Vision

public struct CaptureResult: Sendable {
    public let capture: TackCapture
    public let group: TackGroup
    public let notes: [TackNote]
    public let canvasWidth: Double
    public let canvasHeight: Double
    public let usedFallback: Bool

    public init(capture: TackCapture, group: TackGroup, notes: [TackNote], canvasWidth: Double, canvasHeight: Double, usedFallback: Bool) {
        self.capture = capture
        self.group = group
        self.notes = notes
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.usedFallback = usedFallback
    }
}

public enum TackCaptureError: LocalizedError {
    case unreadableImage(URL)
    case cannotWriteAsset(URL)
    case visionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return "Could not read image: \(url.path)"
        case .cannotWriteAsset(let url): return "Could not write captured asset: \(url.path)"
        case .visionFailed(let message): return "Vision capture failed: \(message)"
        }
    }
}

public enum TackImageCapture {
    public static func capture(
        imageAt sourceURL: URL,
        to packageRoot: URL,
        originX: Double = 80,
        originY: Double = 80,
        groupName: String? = nil
    ) throws -> CaptureResult {
        guard let sourceImage = image(at: sourceURL) else {
            throw TackCaptureError.unreadableImage(sourceURL)
        }

        let captureID = UUID()
        let sourceExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
        let capturePath = "media/captures/\(captureID.uuidString).\(sourceExtension)"
        let captureURL = packageRoot.appendingPathComponent(capturePath)
        try FileManager.default.createDirectory(at: captureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: captureURL.path) {
            try FileManager.default.removeItem(at: captureURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: captureURL)

        let width = Double(sourceImage.width)
        let height = Double(sourceImage.height)
        let displayScale = min(1, 1000 / max(width, 1))
        let observations = try detectRectangles(in: sourceImage)
        let candidates = deduplicated(observations)
        let useFallback = candidates.isEmpty
        let boxes = useFallback ? [CGRect(x: 0, y: 0, width: 1, height: 1)] : candidates.map(\.boundingBox)
        let groupID = UUID()
        let trimmedGroupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGroupName = trimmedGroupName.flatMap { $0.isEmpty ? nil : $0 } ?? "Capture \(Date.now.formatted(date: .abbreviated, time: .shortened))"

        var notes: [TackNote] = []
        for box in boxes {
            let pixelRect = pixelRect(for: box, width: sourceImage.width, height: sourceImage.height)
            guard let crop = sourceImage.cropping(to: pixelRect) else { continue }
            let noteID = UUID()
            let notePath = "media/notes/\(noteID.uuidString).jpg"
            let noteURL = packageRoot.appendingPathComponent(notePath)
            try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeJPEG(crop, to: noteURL)

            let textResult = recognizeText(in: crop)
            let noteWidth = max(100, box.width * width * displayScale)
            let noteHeight = max(100, box.height * height * displayScale)
            let noteX = originX + box.minX * width * displayScale
            let noteY = originY + (1 - box.maxY) * height * displayScale
            let note = TackNote(
                id: noteID,
                frame: TackRect(x: noteX, y: noteY, width: noteWidth, height: noteHeight),
                color: averageColor(in: crop),
                text: textResult.text,
                groupName: resolvedGroupName,
                imagePath: notePath,
                sourceCaptureID: captureID.uuidString,
                ocrConfidence: textResult.confidence,
                isCaptured: true
            )
            notes.append(note)
        }

        let groupFrame = notes.reduce(into: TackRect(x: originX, y: originY, width: 0, height: 0)) { frame, note in
            frame = union(frame, note.frame)
        }
        let group = TackGroup(id: groupID, name: resolvedGroupName, frame: groupFrame, noteIDs: notes.map(\.id))
        let capture = TackCapture(id: captureID, sourceFilename: sourceURL.lastPathComponent, capturedAt: Date(), imagePath: capturePath)
        let canvasWidth = max(1200, originX + width * displayScale + 120)
        let canvasHeight = max(800, originY + height * displayScale + 120)
        return CaptureResult(capture: capture, group: group, notes: notes, canvasWidth: canvasWidth, canvasHeight: canvasHeight, usedFallback: useFallback)
    }

    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func detectRectangles(in image: CGImage) throws -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.45
        request.minimumSize = 0.018
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 5
        request.maximumObservations = 200
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw TackCaptureError.visionFailed(error.localizedDescription)
        }
        return request.results ?? []
    }

    private static func deduplicated(_ observations: [VNRectangleObservation]) -> [VNRectangleObservation] {
        let sorted = observations
            .filter { $0.boundingBox.width * $0.boundingBox.height < 0.72 }
            .sorted { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        var accepted: [VNRectangleObservation] = []
        for observation in sorted {
            let overlaps = accepted.contains { intersectionOverUnion($0.boundingBox, observation.boundingBox) > 0.65 }
            if !overlaps { accepted.append(observation) }
        }
        return accepted.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea == 0 ? 0 : intersectionArea / unionArea
    }

    private static func pixelRect(for normalized: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(
            x: normalized.minX * CGFloat(width),
            y: (1 - normalized.maxY) * CGFloat(height),
            width: normalized.width * CGFloat(width),
            height: normalized.height * CGFloat(height)
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func recognizeText(in image: CGImage) -> (text: String, confidence: Double?) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ("", nil)
        }
        let observations = request.results ?? []
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        let confidence = candidates.isEmpty ? nil : candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
        return (text, confidence)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TackCaptureError.cannotWriteAsset(url)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TackCaptureError.cannotWriteAsset(url) }
    }

    private static func averageColor(in image: CGImage) -> TackColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return TackColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255, alpha: 1)
    }

    private static func union(_ lhs: TackRect, _ rhs: TackRect) -> TackRect {
        if lhs.width == 0 || lhs.height == 0 { return rhs }
        let minX = min(lhs.x, rhs.x)
        let minY = min(lhs.y, rhs.y)
        let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)
        return TackRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
