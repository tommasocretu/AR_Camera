package org.tommasocretu.markerar

import android.util.Log

/**
 * Carica la libreria nativa di OpenCV inclusa nell'AAR `org.opencv:opencv`.
 *
 * Le classi Java di OpenCV (org.opencv.core.*) richiedono `libopencv_java4.so`;
 * il binding dell'app avviene tramite la dipendenza Maven dichiarata
 * dall'export plugin (vedi export_scripts_template/export_plugin.gd).
 */
internal object OpenCVBootstrap {
	private const val LOG_TAG = "MarkerARPlugin"
	private const val NATIVE_LIBRARY = "opencv_java4"

	@Volatile
	private var loaded = false

	fun ensureLoaded(): Boolean {
		if (loaded) {
			return true
		}
		synchronized(this) {
			if (loaded) {
				return true
			}
			return try {
				System.loadLibrary(NATIVE_LIBRARY)
				loaded = true
				Log.d(LOG_TAG, "OpenCV native library loaded ($NATIVE_LIBRARY)")
				true
			} catch (e: UnsatisfiedLinkError) {
				Log.e(LOG_TAG, "OpenCV native library not loadable: $NATIVE_LIBRARY", e)
				false
			}
		}
	}
}
