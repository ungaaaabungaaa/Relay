package dev.ungaaaabungaaa.relay.security

import java.security.MessageDigest

fun canonicalRequest(
    deviceId: String,
    method: String,
    path: String,
    body: ByteArray,
    timestamp: Long,
    nonce: String,
): String {
    val digest = MessageDigest.getInstance("SHA-256")
        .digest(body)
        .joinToString("") { "%02x".format(it) }
    return listOf(
        deviceId,
        method.uppercase(),
        path,
        digest,
        timestamp.toString(),
        nonce,
    ).joinToString("\n")
}
