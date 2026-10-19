//
//  TreemapLayoutTests.swift
//  BytewiseTests
//

import CoreGraphics
import Testing
@testable import Bytewise

struct TreemapLayoutTests {
    @Test func squarifyKeepsAreasProportionalWithoutOverlap() {
        let values: [Double] = [500, 300, 120, 50, 20, 6, 3, 1]
        let box = CGRect(x: 0, y: 0, width: 800, height: 500)
        let rects = TreemapLayout.squarify(values, in: box)
        let total = values.reduce(0, +)

        #expect(rects.count == values.count)
        for (value, rect) in zip(values, rects) {
            #expect(abs(rect.width * rect.height - value / total * 400_000) < 0.01)
            #expect(box.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where i < j {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.width < 0.001 || overlap.height < 0.001)
            }
        }
    }
}
