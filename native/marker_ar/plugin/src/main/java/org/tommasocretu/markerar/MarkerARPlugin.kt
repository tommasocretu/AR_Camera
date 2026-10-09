package org.tommasocretu.markerar

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.util.Log
import android.view.View
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Plugin Android v2 che espone al gioco un feed marker ArUco senza servizi
 * Google: anteprima fotocamera (frame RGBA) e pose dei marker rilevati
 * (OpenCV ArucoDetector + solvePnP).
 *
 * GDScript:
 *   var plugin := Engine.get_singleton("MarkerARPlugin")
 *   plugin.start({...})   # config, vedi MarkerCameraSession.configure()
 *   plugin.connect("frame_available", ...)
 *   plugin.connect("markers_detected", ...)
 */
class MarkerARPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		const val LOG_TAG = "MarkerARPlugin"
		private const val CAMERA_PERMISSION_REQUEST = 2401

		private val CAMERA_PERMISSION_GRANTED = SignalInfo("camera_permission_granted")
		private val CAMERA_PERMISSION_DENIED = SignalInfo("camera_permission_denied")
		private val FRAME_AVAILABLE = SignalInfo("frame_available", Dictionary::class.java)
		private val MARKERS_DETECTED = SignalInfo("markers_detected", Dictionary::class.java)
	}

	private var session: MarkerCameraSession? = null
	private var running = false

	override fun getPluginName(): String = "MarkerARPlugin"

	override fun getPluginSignals(): Set<SignalInfo> = setOf(
		CAMERA_PERMISSION_GRANTED,
		CAMERA_PERMISSION_DENIED,
		FRAME_AVAILABLE,
		MARKERS_DETECTED,
	)

	override fun onMainCreate(activity: Activity): View? {
		Log.d(LOG_TAG, "onMainCreate")
		return null
	}

	override fun onMainResume() {
		Log.d(LOG_TAG, "onMainResume")
		if (running) {
			ensureSession(null)
		}
	}

	override fun onMainPause() {
		Log.d(LOG_TAG, "onMainPause")
		session?.closeCamera()
	}

	override fun onMainDestroy() {
		Log.d(LOG_TAG, "onMainDestroy")
		stop()
	}

	@UsedByGodot
	fun has_camera_permission(): Boolean {
		val activity = activity ?: return false
		return activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
	}

	@UsedByGodot
	fun request_camera_permission() {
		val activity = activity ?: return
		if (has_camera_permission()) {
			Log.d(LOG_TAG, "request_camera_permission: already granted")
			return
		}
		activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
	}

	@UsedByGodot
	fun start(config: Dictionary) {
		if (activity == null) {
			return
		}
		if (!has_camera_permission()) {
			Log.e(LOG_TAG, "start: camera permission not granted")
			return
		}
		running = true
		ensureSession(config)
	}

	@UsedByGodot
	fun stop() {
		running = false
		session?.stop()
		session = null
	}

	@UsedByGodot
	fun get_intrinsics(): Dictionary = session?.intrinsicsData() ?: Dictionary()

	private fun ensureSession(config: Dictionary?) {
		val activity = activity ?: return
		if (session == null) {
			if (!OpenCVBootstrap.ensureLoaded()) {
				Log.e(LOG_TAG, "start: OpenCV native library not available")
				return
			}
			session = MarkerCameraSession(activity, object : MarkerCameraSession.Listener {
				override fun onPreviewFrame(frame: Dictionary) {
					emitOnMainThread(FRAME_AVAILABLE.name, frame)
				}

				override fun onMarkersDetected(data: Dictionary) {
					emitOnMainThread(MARKERS_DETECTED.name, data)
				}

				override fun onError(message: String) {
					Log.e(LOG_TAG, message)
				}
			})
		}
		session?.configure(config)
		session?.openCamera()
	}

	private fun emitOnMainThread(signalName: String, data: Dictionary) {
		val activity = activity ?: return
		activity.runOnUiThread { emitSignal(signalName, data) }
	}

	override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<out String>?, grantResults: IntArray?) {
		super.onMainRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode != CAMERA_PERMISSION_REQUEST) {
			return
		}
		val granted = grantResults?.isNotEmpty() == true && grantResults[0] == PackageManager.PERMISSION_GRANTED
		val activity = activity ?: return
		activity.runOnUiThread {
			if (granted) {
				Log.d(LOG_TAG, "camera permission granted")
				emitSignal(CAMERA_PERMISSION_GRANTED.name)
			} else {
				Log.w(LOG_TAG, "camera permission denied")
				emitSignal(CAMERA_PERMISSION_DENIED.name)
			}
		}
	}
}
