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
import kotlin.math.*

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
            val sampleRate = 8000
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
                val buffer = ShortArray(8192)

                while (isRecording) {
                    val readSize = audioRecord.read(buffer, 0, buffer.size)
                    if (readSize > 0) {
                        val frequency = detectPitch(buffer, sampleRate)
                        if (frequency in 80.0..1000.0) {
                            runOnUiThread {
                                methodChannel?.invokeMethod(
                                    "onFrequencyUpdate",
                                    mapOf("frequency" to frequency)
                                )
                            }
                        }
                    }
                    Thread.sleep(100)
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

    // === FFT-based pitch detection ===
    private fun detectPitch(buffer: ShortArray, sampleRate: Int): Double {
        val n = buffer.size
        if (n < 64) return 0.0

        // 1. Применяем окно Ханна и нормализуем
        val windowed = DoubleArray(n) { i ->
            val window = 0.5 * (1.0 - cos(2 * PI * i / (n - 1)))
            (buffer[i].toDouble() / 32768.0) * window
        }

        // 2. Выполняем FFT
        val fftOut = fft(windowed)

        // 3. Спектр мощности
        val spectrum = DoubleArray(fftOut.size / 2) { i ->
            val re = fftOut[2 * i]
            val im = fftOut[2 * i + 1]
            re * re + im * im
        }

        // 4. Поиск пика в диапазоне 80–1000 Гц
        val minBin = maxOf(1, (80 * spectrum.size / sampleRate).toInt())
        val maxBin = minOf(spectrum.size - 1, (1000 * spectrum.size / sampleRate).toInt())

        if (minBin >= maxBin) return 0.0

        var maxMag = 0.0
        var peakBin = -1
        for (i in minBin..maxBin) {
            if (spectrum[i] > maxMag) {
                maxMag = spectrum[i]
                peakBin = i
            }
        }

        return if (peakBin > 0) {
            peakBin.toDouble() * sampleRate / spectrum.size
        } else {
            0.0
        }
    }

    // Простой рекурсивный FFT (Cooley-Tukey)
    private fun fft(x: DoubleArray): DoubleArray {
        val n = x.size
        if (n <= 1) {
            return doubleArrayOf(x[0], 0.0)
        }

        // Приводим длину к степени двойки
        if (n and (n - 1) != 0) {
            val newSize = Integer.highestOneBit(n) shl 1
            val padded = DoubleArray(newSize)
            x.copyInto(padded)
            return fft(padded)
        }

        // Чётные и нечётные
        val even = DoubleArray(n / 2) { x[2 * it] }
        val odd = DoubleArray(n / 2) { x[2 * it + 1] }

        val evenFft = fft(even)
        val oddFft = fft(odd)

        val result = DoubleArray(n * 2)
        for (k in 0 until n / 2) {
            val angle = -2 * PI * k / n
            val re = cos(angle)
            val im = sin(angle)

            val oddRe = oddFft[2 * k]
            val oddIm = oddFft[2 * k + 1]

            val real = evenFft[2 * k] + re * oddRe - im * oddIm
            val imag = evenFft[2 * k + 1] + re * oddIm + im * oddRe

            result[2 * k] = real
            result[2 * k + 1] = imag
            result[2 * (k + n / 2)] = evenFft[2 * k] - re * oddRe + im * oddIm
            result[2 * (k + n / 2) + 1] = evenFft[2 * k + 1] - re * oddIm - im * oddRe
        }
        return result
    }
}