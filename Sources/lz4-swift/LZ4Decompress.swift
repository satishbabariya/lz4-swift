//
//  LZ4Decompress.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation

public enum LZ4Decompress {

    /// Decompress LZ4 compressed data.
    /// - Parameters:
    ///   - src: Source compressed data
    ///   - dst: Destination buffer (must be large enough)
    /// - Returns: Number of bytes written to dst, or negative error code
    public static func decompress_safe(src: [UInt8], dst: inout [UInt8]) -> Int {
        let srcSize = src.count
        let dstSize = dst.count
        return src.withUnsafeBufferPointer { sPtr in
            return dst.withUnsafeMutableBufferPointer { dPtr in
                return decompress_generic(srcPtr: sPtr.baseAddress!, srcSize: srcSize, dstPtr: dPtr.baseAddress!, dstSize: dstSize, targetOutputSize: dstSize)
            }
        }
    }
    
    /// Decompress LZ4 compressed data partially.
    public static func decompress_safe_partial(src: [UInt8], dst: inout [UInt8], targetOutputSize: Int) -> Int {
        let srcSize = src.count
        let dstSize = dst.count
        return src.withUnsafeBufferPointer { sPtr in
            return dst.withUnsafeMutableBufferPointer { dPtr in
                return decompress_generic(srcPtr: sPtr.baseAddress!, srcSize: srcSize, dstPtr: dPtr.baseAddress!, dstSize: dstSize, targetOutputSize: targetOutputSize)
            }
        }
    }

    /// Decompress with external dictionary.
    public static func decompress_safe_usingDict(src: [UInt8], dst: inout [UInt8], dict: [UInt8]) -> Int {
        let srcSize = src.count
        let dstSize = dst.count
        let dictSize = dict.count
        return src.withUnsafeBufferPointer { sPtr in
            return dst.withUnsafeMutableBufferPointer { dPtr in
                return decompress_generic(srcPtr: sPtr.baseAddress!, srcSize: srcSize, dstPtr: dPtr.baseAddress!, dstSize: dstSize, targetOutputSize: dstSize, dict: dict, dictSize: dictSize)
            }
        }
    }

    /// Decompress using streaming context (which holds dict).
    public static func decompress_safe_continue(_ ctx: LZ4StreamDecode, src: [UInt8], dst: inout [UInt8]) -> Int {
         return decompress_safe_usingDict(src: src, dst: &dst, dict: ctx.dict)
    }

    private static func decompress_generic(srcPtr: UnsafePointer<UInt8>, srcSize: Int, dstPtr: UnsafeMutablePointer<UInt8>, dstSize: Int, targetOutputSize: Int, dict: [UInt8]? = nil, dictSize: Int = 0) -> Int {
        var ip = 0
        let iend = srcSize
        
        var op = 0
        let oend = dstSize
        let oexit = targetOutputSize
        
        // Main loop
        while ip < iend {
            // Get token
            let token = Int(srcPtr[ip])
            ip += 1
            
            // Literal length
            var literalLen = (token >> LZ4Constants.ML_BITS)
            if literalLen == Int(LZ4Constants.RUN_MASK) {
                var s = 255
                while ip < iend && s == 255 {
                    s = Int(srcPtr[ip])
                    ip += 1
                    literalLen += s
                }
            }
            
            // Copy literals
            if op + literalLen > oend - LZ4Constants.WILDCOPYLENGTH {
                if op + literalLen > oend { return -1 } // Error: Output buffer too small
            }
            
            if ip + literalLen > iend { return -2 } // Error: Input overrun for literals
            
            // Fast Copy
            if literalLen > 0 {
                // srcPtr + ip is safe
                // dstPtr + op is safe checked above
                UnsafeMutableRawPointer(dstPtr + op).copyMemory(from: srcPtr + ip, byteCount: literalLen)
                op += literalLen
                ip += literalLen
            }
            
            if ip >= iend || op >= oexit { break }
            
            // Match offset
            if ip + 2 > iend { return -3 }
            let offset = Int(srcPtr[ip]) | (Int(srcPtr[ip+1]) << 8)
            ip += 2
            
            if offset == 0 { return -4 }
            
            // Match length
            var matchLen = (token & Int(LZ4Constants.ML_MASK))
            if matchLen == Int(LZ4Constants.ML_MASK) {
                var s = 255
                while ip < iend && s == 255 {
                    s = Int(srcPtr[ip])
                    ip += 1
                    matchLen += s
                }
            }
            matchLen += LZ4Constants.MINMATCH
            
            if op + matchLen > oend { return -6 } // Error: Output buffer too small for match
            
            // Copy match (Handle ExtDict)
            let matchPtr = op - offset
            
            if matchPtr >= 0 {
                // Within current dst (Prefix)
                
                // Overlap handling:
                // If offset < matchLen, regions overlap.
                // copyMemory handles overlap safely? Documentation says "must not overlap".
                // So we must use a loop if offset < matchLen.
                // Or use `moveInitialize`? No, that's for typed pointers.
                // Simplest/Fastest safe way for small overlaps is byte loop or incremental copy.
                // If offset >= matchLen, we can use copyMemory.
                
                if offset >= matchLen {
                    UnsafeMutableRawPointer(dstPtr + op).copyMemory(from: dstPtr + matchPtr, byteCount: matchLen)
                } else {
                    // Overlap copy
                    if offset == 1 {
                        // RLE optimization (Memset)
                        let byte = dstPtr[matchPtr]
                        UnsafeMutableRawPointer(dstPtr + op).initializeMemory(as: UInt8.self, repeating: byte, count: matchLen)
                    } else {
                        // General overlap (slow path, but rare for long matches usually)
                        for i in 0..<matchLen {
                            dstPtr[op + i] = dstPtr[matchPtr + i]
                        }
                    }
                }
            } else {
                // External Dictionary
                if dict == nil || dictSize == 0 { return -5 } // Error
                
                let dictIndex = dictSize + matchPtr
                if dictIndex < 0 { return -5 } // Too far back
                
                let copyFromDict = min(matchLen, dictSize - dictIndex)
                let copyFromPrefix = matchLen - copyFromDict
                
                if let d = dict {
                     // Dictionary is [UInt8], accessing via subscript is slow?
                     // Can we get a pointer to dict?
                     // Ideally we passed UnsafePointer for dict too.
                     // But dict is Array.
                     // We can optimize this later. For now, loop.
                     for i in 0..<copyFromDict {
                         dstPtr[op + i] = d[dictIndex + i]
                     }
                }
                
                if copyFromPrefix > 0 {
                    for i in 0..<copyFromPrefix {
                        dstPtr[op + copyFromDict + i] = dstPtr[i]
                    }
                }
            }
            op += matchLen
        }
        
        return op
    }
}

public class LZ4StreamDecode {
    public var dict: [UInt8]
    public var dictSize: Int
    
    public init() {
        self.dict = []
        self.dictSize = 0
    }
    
    public func setDict(_ d: [UInt8]) {
        // Keep last 64kb
        if d.count > 65536 {
             let start = d.count - 65536
             self.dict = Array(d[start..<d.count])
        } else {
             self.dict = d
        }
        self.dictSize = self.dict.count
    }
}
