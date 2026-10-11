//
//  RegionBlend.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  A grade inside a mask: the graded picture where the mask is, the
//  original everywhere else, with the edge feathered. The mask is stretched
//  to the picture when their sizes differ — it is found on the picture being
//  graded, so that only happens when a caller resized in between.
//

import CoreGraphics
import CoreImage
import Foundation
import VideoGrade

enum RegionBlend {

    static func grade(_ image: CGImage, _ grade: VideoGrade, within mask: RegionMask) throws -> CGImage {
        guard mask.width > 0, mask.height > 0, mask.pixels.count == mask.width * mask.height else {
            throw ImageForgeError.emptyResult("a region mask of the wrong size")
        }
        let graded = try Renderer.grade(image, grade)
        let original = CIImage(cgImage: image)
        let extent = original.extent
        let matte = try maskImage(mask, fitting: extent)
        guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: CIImage(cgImage: graded),
            kCIInputBackgroundImageKey: original,
            kCIInputMaskImageKey: matte,
        ])?.outputImage else {
            throw ImageForgeError.emptyResult("blending a graded region")
        }
        let context = CIContext(options: [.workingColorSpace: Renderer.usableColorSpace(for: image)])
        guard let rendered = context.createCGImage(blend, from: extent) else {
            throw ImageForgeError.emptyResult("rendering a graded region")
        }
        return rendered
    }

    /// The mask as a feathered grayscale image over `extent`.
    static func maskImage(_ mask: RegionMask, fitting extent: CGRect) throws -> CIImage {
        guard let provider = CGDataProvider(data: mask.pixels as CFData),
              let gray = CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 8,
                                 bytesPerRow: mask.width, space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
                                 shouldInterpolate: true, intent: .defaultIntent) else {
            throw ImageForgeError.emptyResult("reading a region mask")
        }
        var matte = CIImage(cgImage: gray)
        let sx: CGFloat = extent.width / CGFloat(mask.width)
        let sy: CGFloat = extent.height / CGFloat(mask.height)
        if sx != 1 || sy != 1 {
            matte = matte.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        matte = matte.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        if mask.feather > 0 {
            matte = matte.clampedToExtent()
                .applyingGaussianBlur(sigma: mask.feather / 3)   // faded out `feather` px past the edge
                .cropped(to: extent)
        }
        return matte
    }
}
