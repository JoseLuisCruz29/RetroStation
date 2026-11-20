package com.moran.retrostation

import android.media.AudioAttributes
import android.media.SoundPool
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity : FlutterActivity() {
    private var producer: TextureRegistry.SurfaceProducer? = null

    // Multijugador LAN: muchos móviles descartan los paquetes de difusión de
    // la Wi-Fi para ahorrar batería. Mientras se buscan jugadores se pide que
    // los entreguen (MulticastLock).
    private var multicastLock: WifiManager.MulticastLock? = null

    // Durante una partida multijugador: Wi-Fi sin ahorro de energía. Si no,
    // Android duerme la radio unos milisegundos entre paquetes y la latencia
    // sube a 80-100 ms, lo que frena el juego (cada fotograma espera al otro).
    private var lowLatencyLock: WifiManager.WifiLock? = null

    @Suppress("DEPRECATION")
    private fun setLowLatency(enabled: Boolean) {
        if (enabled) {
            if (lowLatencyLock?.isHeld == true) return
            val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            val mode = if (android.os.Build.VERSION.SDK_INT >= 29) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            lowLatencyLock = wifi.createWifiLock(mode, "retrostation-partida").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            lowLatencyLock?.let { if (it.isHeld) it.release() }
            lowLatencyLock = null
        }
    }

    private fun setLanDiscovery(enabled: Boolean) {
        if (enabled) {
            if (multicastLock?.isHeld == true) return
            val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("retrostation-lan").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            multicastLock?.let { if (it.isHeld) it.release() }
            multicastLock = null
        }
    }

    // Efectos de sonido de la interfaz (res/raw, generados con
    // tool/make_ui_sounds.py). SoundPool los tiene en memoria: suenan al
    // instante al tocar, sin el retardo de un reproductor normal.
    private var sounds: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val pending = mutableMapOf<Int, Float>() // pedidos antes de cargar

    private fun playSound(name: String?, volume: Float) {
        val id = soundIds[name] ?: return
        if (id in loaded) sounds?.play(id, volume, volume, 1, 0, 1f) else pending[id] = volume
    }

    private fun loadSounds() {
        val pool = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
        pool.setOnLoadCompleteListener { p, id, status ->
            if (status == 0) {
                loaded += id
                pending.remove(id)?.let { v -> p.play(id, v, v, 1, 0, 1f) }
            }
        }
        mapOf(
            "click" to R.raw.sfx_click,
            "open" to R.raw.sfx_open,
            "back" to R.raw.sfx_back,
            "move" to R.raw.sfx_move,
            "on" to R.raw.sfx_on,
        ).forEach { (name, res) -> soundIds[name] = pool.load(this, res, 1) }
        sounds = pool
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        loadSounds()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retrostation/sfx")
            .setMethodCallHandler { call, result ->
                if (call.method == "play") {
                    playSound(call.argument<String>("name"), (call.argument<Double>("volume") ?: 1.0).toFloat())
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retrostation/lan")
            .setMethodCallHandler { call, result ->
                if (call.method == "discovery") {
                    setLanDiscovery(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                } else if (call.method == "lowLatency") {
                    setLowLatency(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "retrostation/video")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "create" -> {
                        val width = call.argument<Int>("width") ?: 240
                        val height = call.argument<Int>("height") ?: 160
                        result.success(createSurface(flutterEngine, width, height))
                    }
                    "release" -> {
                        releaseSurface()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Crea una superficie que Flutter muestra como textura. El frontend C++
     * escribe cada fotograma directamente en ella (ANativeWindow).
     */
    private fun createSurface(engine: FlutterEngine, width: Int, height: Int): Long {
        releaseSurface()
        val p = engine.renderer.createSurfaceProducer()
        p.setSize(width, height)
        p.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                NativeVideo.setSurface(p.surface)
            }

            override fun onSurfaceCleanup() {
                NativeVideo.setSurface(null)
            }
        })
        NativeVideo.setSurface(p.surface)
        producer = p
        return p.id()
    }

    private fun releaseSurface() {
        producer?.let {
            NativeVideo.setSurface(null)
            it.release()
        }
        producer = null
    }

    override fun onDestroy() {
        setLanDiscovery(false)
        setLowLatency(false)
        sounds?.release()
        sounds = null
        releaseSurface()
        super.onDestroy()
    }
}
