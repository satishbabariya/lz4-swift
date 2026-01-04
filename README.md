# lz4-swift

A high-performance, pure Swift implementation of the LZ4 compression algorithm.

`lz4-swift` provides a safe (and optionally unsafe-optimized) interface to LZ4 compression and decompression, achieving throughputs comparable to C and Rust implementations.

## Features

- **Pure Swift**: No C dependencies, easy to drop into any Swift project.
- **High Performance**:
  - **Decompression**: **~4.6 GB/s**.
  - **Compression**: **~3.6 - 4.8 GB/s** (Excellent for network/disk I/O).
- **LZ4 Frame Support**: Full support for the LZ4 Frame format (interoperable with standard `lz4` CLI).
- **Modern API**: Typesafe `LZ4Stream` and simple `compress`/`decompress` helpers.
- **Cross-Platform**: Works on macOS, Linux, and Windows.

## Performance

Benchmarks run on Apple Silicon (M-series).

| Operation | Dataset | Speed | Notes |
| :--- | :--- | :--- | :--- |
| **Decompression** | Random Data | **4.56 GB/s** | |
| **Compression** | Zeroes | **4.76 GB/s** | Highly optimized match extension |
| **Compression** | Random Data | **3.60 GB/s** | |

## Installation

Add `lz4-swift` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/lz4-swift.git", from: "1.0.0")
]
```

## Usage

### Simple Block Compression

```swift
import lz4_swift

let originalData: [UInt8] = ...
var compressed = [UInt8](repeating: 0, count: LZ4Compress.compressBound(originalData.count))

// Compress
let cSize = LZ4Compress.compress_default(src: originalData, dst: &compressed)
compressed.removeLast(compressed.count - cSize)

// Decompress
var decompressed = [UInt8](repeating: 0, count: originalData.count)
let dSize = LZ4Decompress.decompress_safe(src: compressed, dst: &decompressed)
```

### Frame compression (Standard .lz4 files)

```swift
import lz4_swift

// Compress to .lz4 frame format
let fileData = try Data(contentsOf: bigFile)
let compressedData = LZ4Frame.compress(fileData) 
// Write `compressedData` to .lz4 file

// Decompress
let decompressedData = try LZ4Frame.decompress(compressedData)
```

### Streaming API

```swift
let ctx = LZ4Stream()
// Compress chunk by chunk
let cChunkSize = LZ4Compress.compress_fast_continue(ctx, src: chunk1, dst: &outBuf)
```

## License

BSD 2-Clause License. See [LICENSE](LICENSE) for details.
