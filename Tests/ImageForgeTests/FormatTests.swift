//
//  FormatTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What this machine can actually do, asserted rather than assumed. If a
//  future macOS gains WebP encoding these tests are how it will be noticed.
//

import XCTest
@testable import ImageForge

final class FormatTests: XCTestCase {

    func testTheEverydayFormatsAreWritable() {
        for format in [ImageFormat.png, .jpeg, .heic, .avif, .tiff, .gif] {
            XCTAssertTrue(format.isWritable, "\(format.rawValue) should be writable")
            XCTAssertTrue(format.isReadable, "\(format.rawValue) should be readable")
        }
    }

    func testWebPAndJPEGXLReadButDoNotWrite() {
        // Measured on macOS 27: ImageIO reads 62 types and writes 22, and
        // these two sit in the gap. This is the whole reason `isWritable`
        // asks the system instead of trusting a table.
        XCTAssertTrue(ImageFormat.webp.isReadable)
        XCTAssertFalse(ImageFormat.webp.isWritable)
        XCTAssertTrue(ImageFormat.jpegXL.isReadable)
        XCTAssertFalse(ImageFormat.jpegXL.isWritable)
    }

    func testTheAlternativeToAWebFormatIsTheWritableWebFormat() {
        XCTAssertEqual(FormatSupport.alternative(to: .webp), .avif)
        XCTAssertEqual(FormatSupport.alternative(to: .jpegXL), .avif)
        XCTAssertEqual(FormatSupport.alternative(to: .png), .png, "a writable format is its own alternative")
    }

    func testAskingForAnUnwritableFormatNamesTheWayOut() {
        XCTAssertThrowsError(try FormatSupport.requireWritable(.webp)) { error in
            guard case ImageForgeError.formatNotWritable(let format, let alternative) = error else {
                return XCTFail("expected formatNotWritable, got \(error)")
            }
            XCTAssertEqual(format, .webp)
            XCTAssertEqual(alternative, .avif)
            XCTAssertTrue(error.localizedDescription.contains("avif"),
                          "the message has to name the alternative")
        }
    }

    func testIconContainersAreWritable() {
        XCTAssertTrue(ImageFormat.icns.isWritable)
        XCTAssertTrue(ImageFormat.ico.isWritable)
        XCTAssertTrue(ImageFormat.icns.isIconContainer)
        XCTAssertFalse(ImageFormat.png.isIconContainer)
    }

    func testExtensionsResolveWhateverTheySpellIt() {
        XCTAssertEqual(ImageFormat.named(fileExtension: "JPG"), .jpeg)
        XCTAssertEqual(ImageFormat.named(fileExtension: ".jpeg"), .jpeg)
        XCTAssertEqual(ImageFormat.named(fileExtension: "tif"), .tiff)
        XCTAssertEqual(ImageFormat.named(fileExtension: "heif"), .heic)
        XCTAssertEqual(ImageFormat.named(fileExtension: "jp2"), .jpeg2000)
        XCTAssertNil(ImageFormat.named(fileExtension: "txt"))
    }

    func testTypeIdentifiersRoundTrip() {
        for format in ImageFormat.allCases {
            XCTAssertEqual(ImageFormat.named(typeIdentifier: format.typeIdentifier), format)
        }
    }

    func testAlphaAndLossinessAreDescribedHonestly() {
        XCTAssertFalse(ImageFormat.jpeg.supportsAlpha)
        XCTAssertTrue(ImageFormat.png.supportsAlpha)
        XCTAssertTrue(ImageFormat.jpeg.isLossy)
        XCTAssertFalse(ImageFormat.png.isLossy)
        XCTAssertTrue(ImageFormat.png.supportsAnimation, "an APNG is a PNG")
        XCTAssertFalse(ImageFormat.jpeg.supportsAnimation)
    }

    func testOnlyTheGainMapFormatsClaimGainMaps() {
        XCTAssertTrue(ImageFormat.heic.supportsGainMap)
        XCTAssertTrue(ImageFormat.avif.supportsGainMap)
        XCTAssertTrue(ImageFormat.jpeg.supportsGainMap)
        XCTAssertFalse(ImageFormat.png.supportsGainMap)
    }

    func testIconContainersTakeOnlyTheSizesTheyWereMeasuredToTake() {
        // These sets are measured, and the surprises are the point: `.icns`
        // has no 64 and no 1024, `.ico` stops at 256.
        XCTAssertFalse(IconSizes.supports(64, in: .icns), "icns refuses 64, however odd that reads")
        XCTAssertFalse(IconSizes.supports(1024, in: .icns), "icns refuses 1024 too")
        XCTAssertTrue(IconSizes.supports(512, in: .icns))
        XCTAssertTrue(IconSizes.supports(64, in: .ico))
        XCTAssertFalse(IconSizes.supports(512, in: .ico))
        XCTAssertNil(IconSizes.supported(for: .png), "a PNG is not an icon container")
        XCTAssertEqual(IconSizes.nearest(to: 60, in: .icns), 48)
    }

    func testTheShippedPresetsOnlyUseSizesThatWork() {
        for size in IconSpec.macOS.sizes {
            XCTAssertTrue(IconSizes.supports(size, in: .icns), "\(size) is not a valid icns size")
        }
        for size in IconSpec.windows.sizes + IconSpec.favicon.sizes {
            XCTAssertTrue(IconSizes.supports(size, in: .ico), "\(size) is not a valid ico size")
        }
    }

    func testAnUnsupportedIconSizeIsRefusedBeforeAnythingIsWritten() {
        let image = TestImages.solid(.red, width: 64, height: 64)
        XCTAssertThrowsError(try ImageEncoder.encodeIcon(image, format: .icns,
                                                         spec: IconSpec(sizes: [64]))) { error in
            guard case ImageForgeError.iconSizeUnsupported(_, let size, let supported) = error else {
                return XCTFail("expected iconSizeUnsupported, got \(error)")
            }
            XCTAssertEqual(size, 64)
            XCTAssertEqual(supported, IconSizes.icns)
            XCTAssertTrue(error.localizedDescription.contains("16"),
                          "the message should list what it does take")
        }
    }

    func testColoursRoundTripThroughHex() {
        XCTAssertEqual(ForgeColor(hex: "#FF0000"), .init(red: 1, green: 0, blue: 0))
        XCTAssertEqual(ForgeColor(hex: "f00")?.hex, "#FF0000")
        XCTAssertEqual(ForgeColor(hex: "#00000000")?.alpha, 0)
        XCTAssertEqual(ForgeColor.clear.hex, "#00000000")
        XCTAssertNil(ForgeColor(hex: "nope"))
        XCTAssertNil(ForgeColor(hex: "#12345"))
    }
}
