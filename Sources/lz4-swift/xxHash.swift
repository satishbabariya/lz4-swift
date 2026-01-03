//
//  xxHash.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation

public struct XXH32 {
    private static let PRIME32_1: UInt32 = 2654435761
    private static let PRIME32_2: UInt32 = 2246822519
    private static let PRIME32_3: UInt32 = 3266489917
    private static let PRIME32_4: UInt32 = 668265263
    private static let PRIME32_5: UInt32 = 374761393

    public static func digest(_ input: [UInt8], seed: UInt32 = 0) -> UInt32 {
        let len = input.count
        var h32: UInt32
        var index = 0
        
        if len >= 16 {
            let limit = len - 16
            var v1 = seed &+ PRIME32_1 &+ PRIME32_2
            var v2 = seed &+ PRIME32_2
            var v3 = seed &+ 0
            var v4 = seed &- PRIME32_1
            
            while index <= limit {
                v1 = round(v1, read32(input, index))
                index += 4
                v2 = round(v2, read32(input, index))
                index += 4
                v3 = round(v3, read32(input, index))
                index += 4
                v4 = round(v4, read32(input, index))
                index += 4
            }
            
            h32 = rotateLeft(v1, 1) &+ rotateLeft(v2, 7) &+ rotateLeft(v3, 12) &+ rotateLeft(v4, 18)
            print("XXH32 Debug: v1=\(v1) v2=\(v2) v3=\(v3) v4=\(v4)")
            print("XXH32 Debug: h32_converged=\(h32)")
        } else {
            h32 = seed &+ PRIME32_5
        }
        
        h32 = h32 &+ UInt32(len)
        
        while index <= len - 4 {
            let val = read32(input, index)
            h32 = h32 &+ (val &* PRIME32_3)
            h32 = rotateLeft(h32, 17) &* PRIME32_4
            print("XXH32 S4: idx=\(index) val=\(val) h32=\(h32)")
            index += 4
        }
        
        while index < len {
            h32 = h32 &+ (UInt32(input[index]) &* PRIME32_5)
            h32 = rotateLeft(h32, 11) &* PRIME32_1
            index += 1
        }
        
        h32 ^= h32 >> 15
        h32 = h32 &* 2246822519 // PRIME32_2
        h32 ^= h32 >> 13
        h32 = h32 &* 3266489917 // PRIME32_3
        h32 ^= h32 >> 16
        
        return h32
    }
    
    @inline(__always)
    private static func round(_ acc: UInt32, _ val: UInt32) -> UInt32 {
        var a = acc
        a = a &+ (val &* PRIME32_2)
        a = rotateLeft(a, 13)
        a = a &* PRIME32_1
        return a
    }

    @inline(__always)
    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        return (value << count) | (value >> (32 - count))
    }
    
    @inline(__always)
    private static func read32(_ src: [UInt8], _ index: Int) -> UInt32 {
        // Unsafe but standard
        // In real impl, use UnsafeRawPointer or littleEndian
        return UInt32(src[index]) | (UInt32(src[index+1]) << 8) | (UInt32(src[index+2]) << 16) | (UInt32(src[index+3]) << 24)
    }
}
