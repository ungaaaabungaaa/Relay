package dev.ungaaaabungaaa.relay.data

import java.util.UUID

fun idempotencyKeyFor(vararg parts: String): String = UUID.nameUUIDFromBytes(
    parts.joinToString("\u001F").toByteArray(Charsets.UTF_8),
).toString()
