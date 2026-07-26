package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayFolder
import dev.ungaaaabungaaa.relay.domain.RelayModel
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
import dev.ungaaaabungaaa.relay.domain.RelayTask
import dev.ungaaaabungaaa.relay.domain.parseApprovalRisk
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import dev.ungaaaabungaaa.relay.security.canonicalRequest
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class RelayApi(
    private val preferences: RelayPreferences,
    private val identity: DeviceIdentity,
    private val cloudTransport: RelayCloudTransport? = null,
    private val client: OkHttpClient = OkHttpClient(),
) {
    suspend fun pairLegacy(code: String, name: String) = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("code", code.uppercase())
            .put("name", name)
            .put("publicKey", identity.publicKeyPem())
            .toString()
        val request = Request.Builder()
            .url("${preferences.bridgeUrl}/v1/pair")
            .post(body.toRequestBody(JSON))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Pairing failed")
            preferences.deviceId = JSONObject(response.body.string()).getString("deviceId")
        }
    }

    suspend fun discoverPairing(record: PairingDiscoveryRecord): PairingMac =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(record.origin + PairingContract.sessionPath(record.discoveryToken))
                .get()
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("Pairing session is unavailable")
                val body = JSONObject(response.body.string())
                PairingMac(
                    name = body.getString("macName"),
                    fingerprint = body.getString("macFingerprint"),
                    apiVersion = body.getInt("apiVersion"),
                    expiresAt = body.getLong("expiresAt"),
                )
            }
        }

    suspend fun submitPairing(
        record: PairingDiscoveryRecord,
        code: String,
        metadata: PairingDeviceMetadata,
    ): PendingPairing = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("code", code.uppercase())
            .put("name", metadata.displayName)
            .put("publicKey", identity.publicKeyPem())
            .put("metadata", JSONObject(metadata.toJson()))
            .toString()
        val request = Request.Builder()
            .url(record.origin + PairingContract.sessionPath(record.discoveryToken))
            .post(body.toRequestBody(JSON))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Pairing failed")
            val result = JSONObject(response.body.string())
            PendingPairing(
                pairingId = result.getString("pairingId"),
                pollToken = result.getString("pollToken"),
                expiresAt = result.getLong("expiresAt"),
            )
        }
    }

    suspend fun pollPairing(
        record: PairingDiscoveryRecord,
        pollToken: String,
    ): PairingPollResult = withContext(Dispatchers.IO) {
        val url = okhttp3.HttpUrl.Builder()
            .scheme("https")
            .host(java.net.URI(record.origin).host)
            .apply {
                java.net.URI(record.origin).port.takeIf { it > 0 }?.let(::port)
            }
            .addPathSegments(
                PairingContract.statusPath(record.discoveryToken).trimStart('/'),
            )
            .addQueryParameter("pollToken", pollToken)
            .build()
        val request = Request.Builder().url(url).get().build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Pairing approval expired")
            val body = JSONObject(response.body.string())
            when (body.getString("state")) {
                "pending" -> PairingPollResult.Pending
                "denied" -> PairingPollResult.Denied
                "approved" -> PairingPollResult.Approved(
                    deviceId = body.getString("deviceId"),
                    origin = body.getString("origin"),
                    apiVersion = body.getInt("apiVersion"),
                )
                else -> error("Unsupported pairing response")
            }
        }
    }

    suspend fun tasks(): List<RelayTask> =
        get("/v1/tasks").getJSONArray("data").mapObjects { item ->
            RelayTask(
                id = item.getString("id"),
                title = item.getString("title"),
                status = item.getString("status"),
                cwd = item.getString("cwd"),
                preview = item.optString("preview"),
                updatedAt = item.optLong("updatedAt"),
            )
        }

    suspend fun inbox(): Pair<List<RelayApproval>, List<RelayQuestion>> {
        val response = get("/v1/inbox")
        val approvals = response.getJSONArray("approvals").mapObjects { item ->
            RelayApproval(
                item.getString("id"),
                item.getString("threadId"),
                item.getString("kind"),
                parseApprovalRisk(item.optString("risk").takeIf(String::isNotBlank)),
                item.optJSONArray("riskReasons")?.mapStrings() ?: emptyList(),
                item.optString("command").takeIf { it.isNotBlank() && it != "null" },
                item.optString("cwd").takeIf { it.isNotBlank() && it != "null" },
                item.optString("reason").takeIf { it.isNotBlank() && it != "null" },
            )
        }
        val questions = response.getJSONArray("questions").mapObjects { item ->
            val first = item.getJSONArray("questions").getJSONObject(0)
            RelayQuestion(
                id = item.getString("id"),
                threadId = item.getString("threadId"),
                prompt = first.getString("question"),
                options = first.optJSONArray("options")
                    ?.mapObjects { it.getString("label") }
                    ?: emptyList(),
                questionId = first.getString("id"),
            )
        }
        return approvals to questions
    }

    suspend fun models(): List<RelayModel> =
        get("/v1/models").getJSONArray("data").mapObjects { item ->
            RelayModel(
                item.getString("id"),
                item.getString("name"),
                item.optString("description"),
                item.getJSONArray("efforts").mapStrings(),
                item.getString("defaultEffort"),
            )
        }

    suspend fun folders(path: String = ""): List<RelayFolder> =
        get(
            if (path.isBlank()) {
                "/v1/folders"
            } else {
                "/v1/folders?path=${java.net.URLEncoder.encode(path, "UTF-8")}"
            },
        )
            .getJSONArray("entries")
            .mapObjects { RelayFolder(it.getString("name"), it.getString("path")) }

    suspend fun decideApproval(id: String, approve: Boolean) =
        post(
            "/v1/approvals/$id",
            JSONObject().put("decision", if (approve) "approve" else "deny"),
            idempotencyKeyFor("approval", id, if (approve) "approve" else "deny"),
        )

    suspend fun answerQuestion(id: String, questionId: String, answers: List<String>) =
        post(
            "/v1/questions/$id",
            JSONObject().put("answers", JSONObject().put(questionId, JSONArray(answers))),
            idempotencyKeyFor("question", id, questionId, answers.joinToString("\u001F")),
        )

    suspend fun send(threadId: String, text: String) =
        post("/v1/tasks/$threadId/instructions", JSONObject().put("text", text))

    suspend fun steer(threadId: String, turnId: String, text: String) =
        post(
            "/v1/tasks/$threadId/steer",
            JSONObject().put("turnId", turnId).put("text", text),
        )

    suspend fun stop(threadId: String, turnId: String) =
        post(
            "/v1/tasks/$threadId/stop",
            JSONObject().put("turnId", turnId),
            idempotencyKeyFor("stop", threadId, turnId),
        )

    suspend fun startTask(
        cwd: String,
        model: String,
        effort: String,
        prompt: String,
    ) = post(
        "/v1/tasks",
        JSONObject()
            .put("cwd", cwd)
            .put("model", model)
            .put("effort", effort)
            .put("prompt", prompt),
        )

    suspend fun transcribe(file: File, durationMs: Long): String {
        val body = withContext(Dispatchers.IO) { file.readBytes() }
        val path = "/v1/transcribe?durationMs=$durationMs"
        if (cloudTransport?.isPaired == true) {
            val deviceId = preferences.deviceId ?: error("Watch is not paired")
            val timestamp = System.currentTimeMillis()
            val nonce = UUID.randomUUID().toString()
            val idempotencyKey = UUID.randomUUID().toString()
            val headers = mapOf(
                "x-relay-device" to deviceId,
                "x-relay-timestamp" to timestamp.toString(),
                "x-relay-nonce" to nonce,
                "x-relay-signature" to identity.sign(
                    canonicalRequest(
                        deviceId,
                        "POST",
                        path,
                        body,
                        timestamp,
                        nonce,
                    ),
                ),
                "content-type" to AUDIO.toString(),
                "idempotency-key" to idempotencyKey,
            )
            val response = cloudTransport.voiceRequest(
                path = path,
                headers = headers,
                audio = body,
                durationMs = durationMs,
            )
            if (response.status !in 200..299) {
                val message = runCatching {
                    JSONObject(response.body).optString("error")
                }.getOrNull()
                error(message?.takeIf(String::isNotBlank) ?: "Relay request failed")
            }
            return JSONObject(response.body).getString("transcript")
        }
        val response = request(
            path = path,
            method = "POST",
            body = body,
            idempotencyKey = UUID.randomUUID().toString(),
            contentType = AUDIO,
        )
        return response.getString("transcript")
    }

    private suspend fun get(path: String): JSONObject = request(path, "GET", ByteArray(0))

    private suspend fun post(
        path: String,
        body: JSONObject,
        idempotencyKey: String = UUID.randomUUID().toString(),
    ): JSONObject = request(
        path,
        "POST",
        body.toString().toByteArray(),
        idempotencyKey,
    )

    private suspend fun request(
        path: String,
        method: String,
        body: ByteArray,
        idempotencyKey: String? = null,
        contentType: okhttp3.MediaType = JSON,
    ): JSONObject =
        withContext(Dispatchers.IO) {
            val deviceId = preferences.deviceId ?: error("Watch is not paired")
            val timestamp = System.currentTimeMillis()
            val nonce = UUID.randomUUID().toString()
            val canonical = canonicalRequest(deviceId, method, path, body, timestamp, nonce)
            val signedHeaders = mutableMapOf(
                "x-relay-device" to deviceId,
                "x-relay-timestamp" to timestamp.toString(),
                "x-relay-nonce" to nonce,
                "x-relay-signature" to identity.sign(canonical),
                "content-type" to contentType.toString(),
            )
            idempotencyKey?.let { signedHeaders["idempotency-key"] = it }
            if (cloudTransport?.isPaired == true) {
                check(contentType != AUDIO) { "Voice must use chunked transfer" }
                val response = cloudTransport.request(
                    method = method,
                    path = path,
                    headers = signedHeaders,
                    body = body.decodeToString(),
                )
                if (response.status !in 200..299) {
                    val message = runCatching {
                        JSONObject(response.body).optString("error")
                    }.getOrNull()
                    error(message?.takeIf(String::isNotBlank) ?: "Relay request failed")
                }
                return@withContext JSONObject(response.body)
            }
            val builder = Request.Builder()
                .url("${preferences.bridgeUrl}$path")
            for ((name, value) in signedHeaders) {
                builder.header(name, value)
            }
            if (method == "POST") builder.post(body.toRequestBody(contentType))
            val response = client.newCall(builder.build()).execute()
            response.use {
                val text = it.body.string()
                if (!it.isSuccessful) {
                    val message = runCatching { JSONObject(text).optString("error") }.getOrNull()
                    error(message?.takeIf(String::isNotBlank) ?: "Bridge request failed")
                }
                JSONObject(text)
            }
        }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
        private val AUDIO = "audio/mp4".toMediaType()
    }
}

private inline fun <T> JSONArray.mapObjects(block: (JSONObject) -> T): List<T> =
    List(length()) { index -> block(getJSONObject(index)) }

private fun JSONArray.mapStrings(): List<String> =
    List(length()) { index -> getString(index) }
