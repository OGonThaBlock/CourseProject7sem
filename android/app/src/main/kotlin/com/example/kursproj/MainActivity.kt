package com.example.kursproj

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.lang.Exception

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.kursproj/pitch"
    private var audioThread: Thread? = null
    private var isRecording = false
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startPitchDetection" -> {
                    if (checkAudioPermission()) {
                        startPitchDetection()
                        result.success(null)
                    } else {
                        result.error("PERMISSION_DENIED", "Microphone permission required", null)
                    }
                }
                "stopPitchDetection" -> {
                    stopPitchDetection()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkAudioPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun startPitchDetection() {
        if (isRecording) return
        isRecording = true
        audioThread = Thread {
            val sampleRate = 8000 // достаточно для pitch detection
            val bufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            try {
                audioRecord.startRecording()
                val buffer = ShortArray(bufferSize / 2)

                while (isRecording) {
                    val readSize = audioRecord.read(buffer, 0, buffer.size)
                    if (readSize > 0) {
                        val frequency = detectPitch(buffer, sampleRate)
                        if (frequency > 20 && frequency < 2000) { // фильтр: человеческий диапазон
                            runOnUiThread {
                                methodChannel?.invokeMethod(
                                    "onFrequencyUpdate",
                                    mapOf("frequency" to frequency)
                                )
                            }
                        }
                    }
                    Thread.sleep(100) // обновление 10 раз в секунду
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                try {
                    audioRecord.stop()
                    audioRecord.release()
                } catch (e: IllegalStateException) {
                    // ignore
                }
            }
        }
        audioThread?.start()
    }

    private fun stopPitchDetection() {
        isRecording = false
        audioThread?.join(500)
    }

    // Упрощённый алгоритм автокорреляции
    private fun detectPitch(buffer: ShortArray, sampleRate: Int): Double {
        val size = buffer.size
        if (size < 50) return 0.0

        var maxCorrelation = 0.0
        var bestOffset = -1

        // Пропускаем первые 20 сэмплов (низкие частоты)
        for (offset in 30 until size / 2) {
            var correlation = 0.0
            for (i in 0 until (size - offset)) {
                correlation += (buffer[i].toDouble() * buffer[i + offset])
            }
            if (correlation > maxCorrelation) {
                maxCorrelation = correlation
                bestOffset = offset
            }
        }

        return if (bestOffset > 0) sampleRate.toDouble() / bestOffset else 0.0
    }
}