//
//  RecipeThumbnailsTests.swift
//  BackPlanerTests
//
//  The small pictures of the recipe list.
//

import Testing
import UIKit
@testable import BackPlaner

@Suite("Recipe list thumbnails")
struct RecipeThumbnailsTests {

    private func picture(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    @Test("A photo is scaled down to the row's size, the shape kept")
    func downsamples() throws {
        let small = try #require(RecipeThumbnails.downsampled(picture(width: 1200, height: 800), maxPixelSize: 300))
        #expect(small.size.width == 300)
        #expect(small.size.height == 200)

        let portrait = try #require(RecipeThumbnails.downsampled(picture(width: 600, height: 900), maxPixelSize: 300))
        #expect(portrait.size.width == 200)
        #expect(portrait.size.height == 300)
    }

    @Test("A picture smaller than the row stays as it is; no picture gives nothing")
    func smallAndEmpty() throws {
        let tiny = try #require(RecipeThumbnails.downsampled(picture(width: 80, height: 60), maxPixelSize: 300))
        #expect(tiny.size.width == 80)
        #expect(RecipeThumbnails.downsampled(Data("kein Bild".utf8), maxPixelSize: 300) == nil)
    }
}
