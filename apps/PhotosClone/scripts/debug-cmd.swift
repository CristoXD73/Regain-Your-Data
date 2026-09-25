import Foundation
// Sends a command to a running debug build (see Sources/PhotosClone/Services/DebugHooks.swift).
DistributedNotificationCenter.default().postNotificationName(.init("PhotosClone.debug"), object: CommandLine.arguments.dropFirst().joined(separator: " "), userInfo: nil, deliverImmediately: true)
