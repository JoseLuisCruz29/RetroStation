package com.moran.retrostation

import android.view.Surface

/** Puente JNI con el frontend libretro (native/frontend/rs_frontend.cpp). */
object NativeVideo {
    init {
        System.loadLibrary("retrostation_native")
    }

    /** Asigna (o quita, con null) la superficie donde se dibujan los fotogramas. */
    @JvmStatic
    external fun setSurface(surface: Surface?)
}
