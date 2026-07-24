package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayFolder
import dev.ungaaaabungaaa.relay.domain.RelayModel
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
import dev.ungaaaabungaaa.relay.domain.RelayTask
import dev.ungaaaabungaaa.relay.domain.parseApprovalRisk
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import dev.ungaaaabungaaa.relay.security.canonicalRequest
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
    private val client: OkHttpClient = OkHttpClient(),
) {
    suspend fun pair(code: String, name: String = "Galaxy Watch6") = withContext(Dispatchers.IO) {
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
                item.getString("id"),
                item.getString("threadId"),
                first.getString("question"),
                first.optJSONArray("options")?.mapObjects { it.getString("label") } ?: emptyList(),
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

    suspend fun folders(path: String): List<RelayFolder> =
        get("/v1/folders?path=${java.net.URLEncoder.encode(path, "UTF-8")}")
            .getJSONArray("entries")
            .mapObjects { RelayFolder(it.getString("name"), it.getString("path")) }

    suspend fun decideApproval(id: String, approve: Boolean) =
        post("/v1/approvals/$id", JSONObject().put("decision", if (approve) "approve" else "deny"))

    suspend fun answerQuestion(id: String, questionId: String, answers: List<String>) =
        post(
            "/v1/questions/$id",
            JSONObject().put("answers", JSONObject().put(questionId, JSONArray(answers))),
        )

    suspend fun send(threadId: String, text: String) =
        post("/v1/tasks/$threadId/instructions", JSONObject().put("text", text))

    suspend fun steer(threadId: String, turnId: String, text: String) =
        post(
            "/v1/tasks/$threadId/steer",
            JSONObject().put("turnId", turnId).put("text", text),
        )

    suspend fun stop(threadId: String, turnId: String) =
        post("/v1/tasks/$threadId/stop", JSONObject().put("turnId", turnId))

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

    private suspend fun get(path: String): JSONObject = request(path, "GET", ByteArray(0))

    private suspend fun post(path: String, body: JSONObject): JSONObject =
        request(path, "POST", body.toString().toByteArray())

    private suspend fun request(path: String, method: String, body: ByteArray): JSONObject =
        withContext(Dispatchers.IO) {
            val deviceId = preferences.deviceId ?: error("Watch is not paired")
            val timestamp = System.currentTimeMillis()
            val nonce = UUID.randomUUID().toString()
            val canonical = canonicalRequest(deviceId, method, path, body, timestamp, nonce)
            val builder = Request.Builder()
                .url("${preferences.bridgeUrl}$path")
                .header("x-relay-device", deviceId)
                .header("x-relay-timestamp", timestamp.toString())
                .header("x-relay-nonce", nonce)
                .header("x-relay-signature", identity.sign(canonical))
            if (method == "POST") builder.post(body.toRequestBody(JSON))
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
    }
}

private inline fun <T> JSONArray.mapObjects(block: (JSONObject) -> T): List<T> =
    List(length()) { index -> block(getJSONObject(index)) }

private fun JSONArray.mapStrings(): List<String> =
    List(length()) { index -> getString(index) }
