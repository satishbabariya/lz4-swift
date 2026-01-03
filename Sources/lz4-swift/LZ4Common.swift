//
//  LZ4Common.swift
//  lz4-swift
//
//  Created for LZ4 Swift Port
//

import Foundation

public enum LZ4Constants {
    public static let MEMORY_USAGE: Int = 14
    public static let MAX_INPUT_SIZE: Int = 0x7E000000
    
    public static let HASHLOG: Int = (MEMORY_USAGE - 2)
    public static let HASH_SIZE_U32: Int = (1 << HASHLOG)
    
    public static let MINMATCH: Int = 4
    public static let WILDCOPYLENGTH: Int = 8
    public static let LASTLITERALS: Int = 5
    public static let MFLIMIT: Int = (WILDCOPYLENGTH + MINMATCH)
    
    public static let ML_BITS: Int = 4
    public static let ML_MASK: UInt8 = ((1 << ML_BITS) - 1)
    public static let RUN_BITS: Int = (8 - ML_BITS)
    public static let RUN_MASK: UInt8 = ((1 << RUN_BITS) - 1)
    
    // 32-bit specific
    public static let HASH_32_PRIME: UInt32 = 2654435761
    public static let SKIPSTRENGTH: Int = 6
}
