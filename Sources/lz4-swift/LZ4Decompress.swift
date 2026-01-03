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
        return decompress_generic(src: src, dst: &dst, targetOutputSize: dst.count)
    }
    
    /// Decompress LZ4 compressed data partially.
    /// - Parameters:
    ///   - src: Source compressed data
    ///   - dst: Destination buffer
    ///   - targetOutputSize: Stop decompression after this many bytes
    /// - Returns: Number of bytes written to dst, or negative error code
    public static func decompress_safe_partial(src: [UInt8], dst: inout [UInt8], targetOutputSize: Int) -> Int {
        return decompress_generic(src: src, dst: &dst, targetOutputSize: targetOutputSize)
    }

    /// Decompress with external dictionary.
    public static func decompress_safe_usingDict(src: [UInt8], dst: inout [UInt8], dict: [UInt8]) -> Int {
        return decompress_generic(src: src, dst: &dst, targetOutputSize: dst.count, dict: dict, dictSize: dict.count)
    }

    /// Decompress using streaming context (which holds dict).
    public static func decompress_safe_continue(_ ctx: LZ4StreamDecode, src: [UInt8], dst: inout [UInt8]) -> Int {
         return decompress_safe_usingDict(src: src, dst: &dst, dict: ctx.dict)
    }

    private static func decompress_generic(src: [UInt8], dst: inout [UInt8], targetOutputSize: Int, dict: [UInt8]? = nil, dictSize: Int = 0) -> Int {
        var ip = 0
        let iend = src.count
        
        var op = 0
        let oend = dst.count
        let oexit = targetOutputSize
        
        // Main loop
        while ip < iend {
            // Get token
            let token = Int(src[ip])
            ip += 1
            
            // Literal length
            var literalLen = (token >> LZ4Constants.ML_BITS)
            if literalLen == Int(LZ4Constants.RUN_MASK) {
                var s = 255
                while ip < iend && s == 255 {
                    s = Int(src[ip])
                    ip += 1
                    literalLen += s
                }
            }
            
            // Copy literals
            if op + literalLen > oend - LZ4Constants.WILDCOPYLENGTH {
                if op + literalLen > oend { return -1 }
            }
            
            if ip + literalLen > iend { return -2 }
            
            for i in 0..<literalLen {
                dst[op + i] = src[ip + i]
            }
            op += literalLen
            ip += literalLen
            
            if ip >= iend || op >= oexit { break }
            
            // Match offset
            if ip + 2 > iend { return -3 }
            let offset = Int(src[ip]) | (Int(src[ip+1]) << 8)
            ip += 2
            
            if offset == 0 { return -4 }
            
            // Match length
            var matchLen = (token & Int(LZ4Constants.ML_MASK))
            if matchLen == Int(LZ4Constants.ML_MASK) {
                var s = 255
                while ip < iend && s == 255 {
                    s = Int(src[ip])
                    ip += 1
                    matchLen += s
                }
            }
            matchLen += LZ4Constants.MINMATCH
            
            if op + matchLen > oend { return -6 }
            
            // Copy match (Handle ExtDict)
            let matchPtr = op - offset
            
            if matchPtr >= 0 {
                // Within current dst (Prefix)
                for i in 0..<matchLen {
                    dst[op + i] = dst[matchPtr + i]
                }
            } else {
                // External Dictionary
                if dict == nil || dictSize == 0 { return -5 } // Error
                
                let dictIndex = dictSize + matchPtr
                if dictIndex < 0 { return -5 } // Too far back
                
                let copyFromDict = min(matchLen, dictSize - dictIndex)
                let copyFromPrefix = matchLen - copyFromDict
                
                if let d = dict {
                     for i in 0..<copyFromDict {
                         dst[op + i] = d[dictIndex + i]
                     }
                }
                
                if copyFromPrefix > 0 {
                    for i in 0..<copyFromPrefix {
                        dst[op + copyFromDict + i] = dst[i]
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
