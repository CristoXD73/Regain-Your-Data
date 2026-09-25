import AVFoundation
import Foundation

/// Serves an in-memory video to AVFoundation, with byte-range support for seeking.
final class MemoryLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let queue = DispatchQueue(label: "WhatsVault.MemoryLoader")
    let data: Data
    let type: String

    init(data: Data, type: String) {
        self.data = data
        self.type = type
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = type
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = true
        }
        if let dr = request.dataRequest {
            let start = Int(dr.requestedOffset)
            let end = dr.requestsAllDataToEndOfResource ? data.count : min(data.count, Int(dr.requestedOffset) + dr.requestedLength)
            if start < end { dr.respond(with: data.subdata(in: start..<end)) }
        }
        request.finishLoading()
        return true
    }
}


actor AsyncGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func enter() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
