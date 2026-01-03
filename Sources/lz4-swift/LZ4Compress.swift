//
//  LZ4Compress.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum LZ4Compress {
    
    @inline(__always)
    private static func hash(_ value: UInt32) -> Int {
        return Int((value &* LZ4Constants.HASH_32_PRIME) >> (32 - LZ4Constants.HASHLOG))
    }
    
    // MARK: - Public API
    
    /// Compress data using default configuration.
    public static func compress_default(src: [UInt8], dst: inout [UInt8]) -> Int {
        let ctx = LZ4Stream() // Temp context
        let srcSize = src.count
        let maxDstSize = dst.count
        return src.withUnsafeBufferPointer { sPtr in
            return dst.withUnsafeMutableBufferPointer { dPtr in
                return compress_generic(ctx, srcPtr: sPtr.baseAddress!, srcSize: srcSize, dstPtr: dPtr.baseAddress!, maxDstSize: maxDstSize, acceleration: 1)
            }
        }
    }
    
    /// Calculate maximum output size for a given input size
    public static func compressBound(_ isize: Int) -> Int {
        return isize + (isize / 255) + 16
    }
    
    /// Compress data using a streaming context.
    public static func compress_fast_continue(_ ctx: LZ4Stream, src: [UInt8], dst: inout [UInt8], acceleration: Int = 1) -> Int {
        let srcSize = src.count
        let maxDstSize = dst.count
        let result = src.withUnsafeBufferPointer { sPtr in
            return dst.withUnsafeMutableBufferPointer { dPtr in
                 return compress_generic(ctx, srcPtr: sPtr.baseAddress!, srcSize: srcSize, dstPtr: dPtr.baseAddress!, maxDstSize: maxDstSize, acceleration: acceleration)
            }
        }
        
        // Update Streaming Context
        ctx.processedBytes += src.count
        
        // Update Dictionary
        // Strategy: Keep last 64KB.
        if src.count >= LZ4Stream.DICT_SIZE {
            // New data is larger than dict size, so dict becomes tail of src
            let start = src.count - LZ4Stream.DICT_SIZE
            for i in 0..<LZ4Stream.DICT_SIZE {
                ctx.dict[i] = src[start + i]
            }
            ctx.dictSize = LZ4Stream.DICT_SIZE
        } else {
             // Append new data to dict
             let newSize = ctx.dictSize + src.count
             if newSize > LZ4Stream.DICT_SIZE {
                 // Shift to make room
                 let overflow = newSize - LZ4Stream.DICT_SIZE
                 let keep = ctx.dictSize - overflow
                 for i in 0..<keep {
                     ctx.dict[i] = ctx.dict[i + overflow]
                 }
                 ctx.dictSize = keep
             }
             
             // Copy src
             for i in 0..<src.count {
                 ctx.dict[ctx.dictSize + i] = src[i]
             }
             ctx.dictSize += src.count
        }
        
        return result
    }

    // MARK: - Internal Generic Compression
    
    private static func compress_generic(_ ctx: LZ4Stream, srcPtr: UnsafePointer<UInt8>, srcSize: Int, dstPtr: UnsafeMutablePointer<UInt8>, maxDstSize: Int, acceleration: Int) -> Int {
        
        // Handle small inputs
        if srcSize < LZ4Constants.MINMATCH + 1 {
            let litLen = srcSize
            var op = 0
            if op + litLen + 1 > maxDstSize { return 0 }
            
            // Encode Token
            if litLen >= 15 {
                dstPtr[op] = 0xF0; op += 1
                var l = litLen - 15
                while l >= 255 {
                    dstPtr[op] = 255; op += 1
                    l -= 255
                }
                dstPtr[op] = UInt8(l); op += 1
            } else {
                dstPtr[op] = UInt8(litLen << 4); op += 1
            }
            
            // Optimized Copy
            UnsafeMutableRawPointer(dstPtr + op).copyMemory(from: srcPtr, byteCount: litLen)
            op += litLen
            return op
        }
        
        var ip = 0
        var anchor = 0
        let iend = srcSize
        let mflimit = iend - LZ4Constants.MFLIMIT
        let matchlimit = iend - LZ4Constants.LASTLITERALS
        
        var op = 0
        let oend = maxDstSize
        
        // Streaming Context
        let baseIp = ctx.processedBytes
        let dictSize = ctx.dictSize
        
        // Use separate pointers for dict and hash table for speed (hoist)
        let hashTable = ctx.hashTable
        let lowLimit = baseIp - dictSize
        
        // Setup Hash Table Init
        if baseIp == 0 && srcSize >= 4 {
             hashTable[hash(read32(srcPtr, 0))] = 0
        }
        
        ip += 1
        var forwardH = hash(read32(srcPtr, ip))
        
        while ip < mflimit {
            var matchIndex = 0
            var findMatchAttempts = (1 << LZ4Constants.SKIPSTRENGTH) + 3
            if acceleration > 1 {
                 findMatchAttempts = findMatchAttempts / acceleration
            }

            var forwardIp = ip
            
            outer: while true {
                 let h = forwardH
                 let current = forwardIp
                 forwardIp += acceleration
                 
                 if forwardIp + 4 > iend { break } 
                 
                 forwardH = hash(read32(srcPtr, forwardIp > mflimit ? mflimit : forwardIp)) 
                 
                 let matchAbsIndex = Int(hashTable[h])
                 hashTable[h] = Int32(baseIp + current)
                 
                 // Distance check (MAX_DISTANCE=64k)
                 let currentAbs = baseIp + current
                 if (matchAbsIndex >= lowLimit) && 
                    (matchAbsIndex < currentAbs) && 
                    (currentAbs - matchAbsIndex <= 65535) {
                      
                      let matchVal: UInt32
                      if matchAbsIndex >= baseIp {
                          matchVal = read32(srcPtr, matchAbsIndex - baseIp)
                      } else {
                          matchVal = read32_dict(ctx.dict, matchAbsIndex, baseIp, dictSize)
                      }
                      
                      if matchVal == read32(srcPtr, current) {
                          matchIndex = matchAbsIndex
                          ip = current
                          break // Found match
                      }
                 }
                 
                 findMatchAttempts -= 1
                 if findMatchAttempts == 0 {
                      // Optimization: Step forward by more than 1 if literals are long
                      let step = 1 + ((ip - anchor) >> 5)
                      ip += step
                      if ip >= mflimit { break outer }
                      forwardIp = ip
                      // Reset attempts
                      findMatchAttempts = (1 << LZ4Constants.SKIPSTRENGTH) + 3
                      if acceleration > 1 {
                           findMatchAttempts = findMatchAttempts / acceleration
                      }
                      
                      forwardH = hash(read32(srcPtr, ip))
                      continue 
                 }
            }

            // Check if we exited due to no match found (end of input)
            if ip >= mflimit { break }

            // Catch up (Backwards match)
            while ip > anchor && matchIndex > lowLimit {
                let mByte: UInt8
                if (matchIndex - 1) >= baseIp {
                    mByte = srcPtr[(matchIndex - 1) - baseIp]
                } else {
                    mByte = ctx.dict[(matchIndex - 1) - (baseIp - dictSize)]
                }
                
                if srcPtr[ip-1] == mByte {
                    ip -= 1
                    matchIndex -= 1
                } else {
                    break
                }
            }
            
            // Encode Literals
            let litLen = ip - anchor
            var token = op
            op += 1
            
            if op + litLen + 10 > oend { return 0 }
            
            if litLen >= 15 {
                dstPtr[token] = 0xF0
                var l = litLen - 15
                while l >= 255 {
                    dstPtr[op] = 255; op += 1
                    l -= 255
                }
                dstPtr[op] = UInt8(l); op += 1
            } else {
                dstPtr[token] = UInt8(litLen << 4)
            }
            
            // Optimized Copy
            UnsafeMutableRawPointer(dstPtr + op).copyMemory(from: srcPtr + anchor, byteCount: litLen)
            op += litLen
            
            // Encode Match
            while true {
                // Offset = current - match
                let currentAbs = baseIp + ip
                let offset = currentAbs - matchIndex
                
                dstPtr[op] = UInt8(offset & 0xff); op += 1
                dstPtr[op] = UInt8( (offset >> 8) & 0xff ); op += 1
                
                // Match Length
                ip += LZ4Constants.MINMATCH
                matchIndex += LZ4Constants.MINMATCH
                
                anchor = ip
                
                // Forward match extend
                
                // SIMD Optimization (Prefix only)
                while ip < matchlimit - 16 {
                    if matchIndex >= baseIp {
                        let p1 = UnsafeRawPointer(srcPtr).advanced(by: ip)
                        let p2 = UnsafeRawPointer(srcPtr).advanced(by: matchIndex - baseIp)
                        
                        var v1 = SIMD16<UInt8>.zero
                        var v2 = SIMD16<UInt8>.zero
                        
                        withUnsafeMutableBytes(of: &v1) { vPtr in
                            vPtr.copyMemory(from: UnsafeRawBufferPointer(start: p1, count: 16))
                        }
                        withUnsafeMutableBytes(of: &v2) { vPtr in
                            vPtr.copyMemory(from: UnsafeRawBufferPointer(start: p2, count: 16))
                        }
                        
                        if v1 == v2 {
                            ip += 16
                            matchIndex += 16
                            continue
                        }
                    }
                    break // Fallback to byte check
                }
                
                while ip < matchlimit {
                    let sByte = srcPtr[ip]
                    let mByte: UInt8
                    
                    if matchIndex >= baseIp {
                        if matchIndex - baseIp >= srcSize { break }
                        mByte = srcPtr[matchIndex - baseIp]
                    } else {
                         if matchIndex < lowLimit { break }
                         mByte = ctx.dict[matchIndex - (baseIp - dictSize)]
                    }
                    
                    if sByte == mByte {
                        ip += 1
                        matchIndex += 1
                    } else {
                        break
                    }
                }
                
                let matchLen = ip - anchor
                
                if matchLen >= 15 {
                    dstPtr[token] += 0x0F
                    var l = matchLen - 15
                    while l >= 255 {
                        dstPtr[op] = 255; op += 1
                        l -= 255
                    }
                    dstPtr[op] = UInt8(l); op += 1
                } else {
                    dstPtr[token] += UInt8(matchLen)
                }
                
                anchor = ip
                
                if ip >= mflimit { break }
                
                // Fill Hash
                let hPos = baseIp + ip - 2
                hashTable[hash(read32(srcPtr, hPos - baseIp))] = Int32(hPos)
                
                // Test next
                let h = hash(read32(srcPtr, ip))
                let nextMatchAbs = Int(hashTable[h])
                hashTable[h] = Int32(baseIp + ip)
                
                let curAbs = baseIp + ip
                if (curAbs - nextMatchAbs < 65535) && (nextMatchAbs < curAbs) && (nextMatchAbs >= lowLimit) {
                    let matchVal: UInt32
                    if nextMatchAbs >= baseIp {
                        matchVal = read32(srcPtr, nextMatchAbs - baseIp)
                    } else {
                        matchVal = read32_dict(ctx.dict, nextMatchAbs, baseIp, dictSize)
                    }
                    
                    if matchVal == read32(srcPtr, ip) {
                        matchIndex = nextMatchAbs
                        token = op
                        op += 1
                        dstPtr[token] = 0
                        continue
                    }
                }
                
                break
            }
        }
        
        // Last literals
        let litLen = iend - anchor
        let token = op
        op += 1
        
        if op + litLen + 5 > oend { return 0 }
        
        if litLen >= 15 {
            dstPtr[token] = 0xF0
            var l = litLen - 15
            while l >= 255 {
                dstPtr[op] = 255; op += 1
                l -= 255
            }
            dstPtr[op] = UInt8(l); op += 1
        } else {
            dstPtr[token] = UInt8(litLen << 4)
        }
        
        // Optimized Copy
        UnsafeMutableRawPointer(dstPtr + op).copyMemory(from: srcPtr + anchor, byteCount: litLen)
        op += litLen
        
        return op
    }
    
    @inline(__always)
    private static func read32(_ src: UnsafePointer<UInt8>, _ index: Int) -> UInt32 {
        var val: UInt32 = 0
        withUnsafeMutableBytes(of: &val) { ptr in
            ptr.copyMemory(from: UnsafeRawBufferPointer(start: src + index, count: 4))
        }
        return val
    }
    
    @inline(__always)
    private static func read32_dict(_ dict: [UInt8], _ absIndex: Int, _ baseIp: Int, _ dictSize: Int) -> UInt32 {
        let offset = absIndex - (baseIp - dictSize)
        if offset < 0 { return 0 } // Should not happen
        
        if offset + 4 <= dict.count {
            // Contiguous in dict
            let b0 = UInt32(dict[offset])
            let b1 = UInt32(dict[offset+1])
            let b2 = UInt32(dict[offset+2])
            let b3 = UInt32(dict[offset+3])
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        } else {
            // Split (rare if dict is large, but possible)
            // Wait, we only read from dict if absIndex < baseIp.
            // So we can read AT MOST up to the end of dict.
            // If offset + 4 > dict.count, it means we cross into src?
            // But absIndex < baseIp.
            // Only if request extends past baseIp.
            // read32 needs 4 bytes.
            // If absIndex = baseIp - 2. We need baseIp-2, baseIp-1 (Dict), baseIp, baseIp+1 (Src).
            // This is "ExtDict" behavior.
            // NOT SUPPORTED fully here yet without passing `src`.
            // But we can simplify: we don't find matches crossing boundary easily in Basic mode.
            // However, `read32` is for Hash comparison.
            // If we can't read 4 bytes, we just return 0 (no match).
            return 0
        }
    }
}
