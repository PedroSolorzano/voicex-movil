package com.pedrosolorzano.voicex_movil

import android.content.Intent
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives EPUBs opened with "Open with VoiceX" or shared into the app.
 *
 * Extends [AudioServiceActivity], not FlutterActivity: audio_service runs the
 * playback handler on a FlutterEngine it owns, and the activity has to attach
 * to that same engine. With a plain FlutterActivity the app gets a second,
 * isolated engine, the service never finds a handler, and the media
 * notification and lock-screen controls silently never appear — even though
 * audio plays normally.
 *
 * Done with a plain MethodChannel rather than a share-intent plugin: the
 * available plugin needs compileSdk 37 and a Gradle API this project does not
 * have. The incoming content:// URI is only readable while the granting intent
 * is alive, so the bytes are copied into cacheDir before the path crosses to
 * Dart, where the library then imports it into permanent storage.
 */
class MainActivity : AudioServiceActivity() {

    private val channelName = "voicex/shared_epub"
    private var channel: MethodChannel? = null

    /** Path captured before Dart was ready to receive it. */
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart asks for the intent that launched the app.
                "getInitialFile" -> {
                    val path = pendingPath ?: extractEpub(intent)
                    pendingPath = null
                    result.success(path)
                }
                // Hands a word to any app that can process text — a translator,
                // typically. The offline answer when the dictionary is
                // unreachable, and the only one for Spanish.
                "processText" -> {
                    val word = call.arguments as? String
                    if (word.isNullOrBlank()) {
                        result.error("EMPTY", "Palabra vacía", null)
                    } else {
                        result.success(processText(word))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractEpub(intent) ?: return
        // Channel is null if the engine has not attached yet; hold until asked.
        if (channel == null) pendingPath = path
        else channel?.invokeMethod("onFile", path)
    }

    private fun processText(word: String): Boolean {
        val intent = Intent(Intent.ACTION_PROCESS_TEXT).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_PROCESS_TEXT, word)
            putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
        }
        // A chooser rather than the default handler: the useful target is
        // usually a translator, which is rarely anyone's default for text.
        val chooser = Intent.createChooser(intent, "Buscar \"$word\" en")
        return try {
            startActivity(chooser)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun extractEpub(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        return uri?.let { copyToCache(it) }
    }

    private fun copyToCache(uri: Uri): String? = try {
        val name = displayName(uri) ?: "compartido.epub"
        val safe = if (name.endsWith(".epub", true)) name else "$name.epub"
        val dest = File(cacheDir, "shared_${System.currentTimeMillis()}_$safe")
        contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
        if (dest.length() > 0) dest.absolutePath else null
    } catch (e: Exception) {
        null
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
    } catch (e: Exception) {
        null
    }
}
