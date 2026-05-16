// Models.swift
// VideoEditor – Core data models

import UIKit
import AVFoundation
import CoreImage

// MARK: - Text Overlay

struct TextOverlay {
    var id: UUID = UUID()
    var text: String = "Sample Text"
    var fontName: String = "Helvetica-Bold"
    var fontSize: CGFloat = 48
    var color: UIColor = .white
    var strokeColor: UIColor = .black
    var strokeWidth: CGFloat = 2
    /// Normalised 0–1 position relative to video frame (origin = top-left)
    var normalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var startTime: CMTime = .zero
    var endTime: CMTime = CMTime(seconds: 99999, preferredTimescale: 600)
}

// MARK: - Video Filter

enum VideoFilter: String, CaseIterable {
    case none    = "None"
//    case vivid   = "Vivid"
    case noir    = "Noir"
    case fade    = "Fade"
    case chrome  = "Chrome"
    case instant = "Instant"
    case cool    = "Cool"
    case warm    = "Warm"

    var icon: String {
        switch self {
        case .none:    return "circle.slash"
//        case .vivid:   return "sun.max.fill"
        case .noir:    return "moon.fill"
        case .fade:    return "aqi.low"
        case .chrome:  return "circle.hexagongrid.fill"
        case .instant: return "camera.filters"
        case .cool:    return "snowflake"
        case .warm:    return "flame.fill"
        }
    }

    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .noir:
            let f = CIFilter(name: "CIPhotoEffectNoir")!
            f.setValue(image, forKey: kCIInputImageKey)
            return f.outputImage ?? image
        case .fade:
            let f = CIFilter(name: "CIPhotoEffectFade")!
            f.setValue(image, forKey: kCIInputImageKey)
            return f.outputImage ?? image
        case .chrome:
            let f = CIFilter(name: "CIPhotoEffectChrome")!
            f.setValue(image, forKey: kCIInputImageKey)
            return f.outputImage ?? image
        case .instant:
            let f = CIFilter(name: "CIPhotoEffectInstant")!
            f.setValue(image, forKey: kCIInputImageKey)
            return f.outputImage ?? image
        case .cool:
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 4000, y: 0), forKey: "inputNeutral")
            return f.outputImage ?? image
        case .warm:
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 8500, y: 0), forKey: "inputNeutral")
            return f.outputImage ?? image
        }
    }
}

// MARK: - Blur Type

enum BlurType: String, CaseIterable {
    case none       = "None"
    case gaussian   = "Gaussian"
    case motion     = "Motion"

    var icon: String {
        switch self {
        case .none:     return "circle.slash"
        case .gaussian: return "aqi.medium"
        case .motion:   return "arrow.right.to.line"
        }
    }

    func apply(to image: CIImage, intensity: Float) -> CIImage {
        switch self {
        case .none: return image
        case .gaussian:
            guard let f = CIFilter(name: "CIGaussianBlur") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(intensity, forKey: kCIInputRadiusKey)
            return (f.outputImage ?? image).cropped(to: image.extent)
        case .motion:
            guard let f = CIFilter(name: "CIMotionBlur") else { return image }
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(intensity, forKey: kCIInputRadiusKey)
            f.setValue(0.0, forKey: kCIInputAngleKey)
            return (f.outputImage ?? image).cropped(to: image.extent)
        }
    }
}

// MARK: - Edit State

final class EditState {
    var assetURL: URL?
    var asset: AVURLAsset? { assetURL.map { AVURLAsset(url: $0) } }

    var trimStart: CMTime = .zero
    var trimEnd:   CMTime = .indefinite

    var textOverlays: [TextOverlay] = []
    var filter:       VideoFilter   = .none
    var speed:        Float         = 1.0
    var blurType:     BlurType      = .none
    var blurIntensity: Float        = 8.0
}

// MARK: - Export Options

struct ExportOptions {
    var fps: Int = 30

    enum Quality: String, CaseIterable {
        case sd   = "480p SD"
        case hd   = "720p HD"
        case fhd  = "1080p FHD"
        case orig = "Original"

        var preset: String {
            switch self {
            case .sd:   return AVAssetExportPreset640x480
            case .hd:   return AVAssetExportPreset1280x720
            case .fhd:  return AVAssetExportPreset1920x1080
            case .orig: return AVAssetExportPresetHighestQuality
            }
        }
    }
    var quality: Quality = .hd
}
