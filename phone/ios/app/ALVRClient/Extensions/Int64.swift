//
//  Int64.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import Foundation
import simd

extension Int64 {
    static func getCurrentMillis() -> Int64 {
        return Int64(NSDate().timeIntervalSince1970 * 1000)
    }
}

/// ALVR timestamps are nanoseconds; mach_absolute_time() counts ticks (~41.67 ns on iPhone).
enum Clock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nowNs() -> UInt64 {
        return mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
    var rightAxis: SIMD3<Float> { SIMD3(columns.0.x, columns.0.y, columns.0.z) }
    var rotation3x3: simd_float3x3 {
        simd_float3x3(SIMD3(columns.0.x, columns.0.y, columns.0.z),
                      SIMD3(columns.1.x, columns.1.y, columns.1.z),
                      SIMD3(columns.2.x, columns.2.y, columns.2.z))
    }
    /// The same rotation with the translation removed.
    var rotationOnly: simd_float4x4 {
        var m = self
        m.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        return m
    }
}
