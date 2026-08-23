// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ElevenViewsBridgeIPC

// On-Mac proof client for the signed XPC bridge (ELE-3160).
//
// Usage:
//   bridge-harness <machServiceName> <capability> <scope> [--approval <token>]
//
// The harness connects to the running listener over XPC, sends one
// BridgeRequest, and prints the returned BridgeReceipt. Because the listener
// reads the caller's *verified* code signature from the connection audit token,
// this binary must be signed with a signing identifier that appears in
// Tools/bridge/trusted-callers.v1.json for an allow decision.
//
// The transport-independent decision table is proven everywhere by
// Tools/bridge/bridge_ipc_proof.py; this binary proves the real XPC hop on a Mac.

func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

let args = CommandLine.arguments
guard args.count >= 4, let scope = BridgeScope(rawValue: args[3]) else {
    FileHandle.standardError.write(Data("usage: bridge-harness <machService> <capability> <scope> [--approval <token>]\n".utf8))
    exit(64)
}

let machService = args[1]
let capability = args[2]

var approval: BridgeApproval?
if let idx = args.firstIndex(of: "--approval"), idx + 1 < args.count {
    approval = BridgeApproval(token: args[idx + 1], grantedBy: .localUserAction,
                              grantedAt: iso(Date()),
                              expiresAt: iso(Date().addingTimeInterval(300)))
}

let request = BridgeRequest(
    requestId: UUID().uuidString,
    capability: capability,
    scope: scope,
    caller: BridgeCaller(id: "io.elevenviews.tools.bridge-harness", name: "Bridge IPC proof harness"),
    approval: approval,
    requestedAt: iso(Date()))

#if canImport(XPC)
import XPC

let payload = try JSONEncoder().encode(request)
let connection = xpc_connection_create_mach_service(machService, nil, 0)
xpc_connection_set_event_handler(connection) { _ in }
xpc_connection_resume(connection)

let message = xpc_dictionary_create(nil, nil, 0)
payload.withUnsafeBytes { raw in
    xpc_dictionary_set_data(message, BridgeMessageEnvelope.payloadKey, raw.baseAddress, raw.count)
}

let reply = xpc_connection_send_message_with_reply_sync(connection, message)
guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY else {
    FileHandle.standardError.write(Data("bridge: no dictionary reply\n".utf8))
    exit(70)
}

var length = 0
guard let ptr = xpc_dictionary_get_data(reply, BridgeMessageEnvelope.payloadKey, &length) else {
    FileHandle.standardError.write(Data("bridge: reply missing payload\n".utf8))
    exit(70)
}

let receipt = try JSONDecoder().decode(BridgeReceipt.self, from: Data(bytes: ptr, count: length))
let pretty = JSONEncoder()
pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try pretty.encode(receipt))
FileHandle.standardOutput.write(Data("\n".utf8))
exit(receipt.outcome == .success ? 0 : 1)
#else
FileHandle.standardError.write(Data("bridge-harness requires XPC (macOS).\n".utf8))
exit(69)
#endif
