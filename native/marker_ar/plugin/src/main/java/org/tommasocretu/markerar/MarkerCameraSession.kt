package org.tommasocretu.markerar

import android.app.Activity
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.SessionConfiguration
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.WindowManager
import org.godotengine.godot.Dictionary
import java.util.Collections
import java.util.concurrent.Executor
import kotlin.math.abs
import kotlin.math.tan

/**
 * Sessione Camera2 per il backend marker.
 *
 * Responsabilita':
 *  - apre la fotocamera posteriore con un ImageReader YUV_420_888;
 *  - emette frame RGBA "upright" (ruotati e scalati) per l'anteprima;
 *  - rileva i marker ArUco sul piano Y grezzo e stima la posa in coordinate
 *    Godot, compensando la rotazione del frame.
 *
 * I callback del listener vengono invocati sul thread della fotocamera: il
 * plugin si occupa di rimbalzarli sul main thread di Godot.
 */
internal class MarkerCameraSession(
	private val activity: Activity,
	private val listener: Listener,
) {

	interface Listener {
		fun onPreviewFrame(frame: Dictionary)
		fun onMarkersDetected(data: Dictionary)
		fun onError(message: String)
	}

	companion object {
		private const val LOG_TAG = "MarkerARPlugin"
		const val DEFAULT_CAPTURE_WIDTH = 1280
		const val DEFAULT_CAPTURE_HEIGHT = 720
		const val DEFAULT_PREVIEW_WIDTH = 540
		const val DEFAULT_PREVIEW_HEIGHT = 960
		const val DEFAULT_MARKER_SIZE = 0.12
	}

	private var camera: CameraDevice? = null
	private var captureSession: CameraCaptureSession? = null
	private var reader: ImageReader? = null
	private var thread: HandlerThread? = null
	private var handler: Handler? = null

	private var running = false
	private var frameCounter = 0

	private var cameraId: String? = null
	private var sensorOrientation = 0
	private var isFrontFacing = false

	private var captureWidth = DEFAULT_CAPTURE_WIDTH
	private var captureHeight = DEFAULT_CAPTURE_HEIGHT
	private var previewWidth = DEFAULT_PREVIEW_WIDTH
	private var previewHeight = DEFAULT_PREVIEW_HEIGHT
	private var previewEvery = 2
	private var detectEvery = 3
	private var autoUpright = true
	private var fixedRotation = 0
	private var markerDictionary = ArucoPoseEstimator.DEFAULT_DICTIONARY_NAME
	private var markerSize = DEFAULT_MARKER_SIZE

	// Intrinsics nello spazio dei pixel del frame di cattura (non ruotato).
	private var fx = 0.0
	private var fy = 0.0
	private var cx = 0.0
	private var cy = 0.0
	private var intrinsicsReady = false

	private val estimator = ArucoPoseEstimator()

	// -- Configurazione --------------------------------------------------------

	fun configure(config: Dictionary?) {
		if (config == null) {
			estimator.configure(markerDictionary, markerSize)
			return
		}
		cameraId = config.stringOr("camera_id", null)
		captureWidth = config.intOr("capture_width", captureWidth)
		captureHeight = config.intOr("capture_height", captureHeight)
		previewWidth = config.intOr("preview_width", previewWidth)
		previewHeight = config.intOr("preview_height", previewHeight)
		previewEvery = maxOf(1, config.intOr("preview_every_frames", previewEvery))
		detectEvery = maxOf(1, config.intOr("detect_every_frames", detectEvery))
		autoUpright = config.boolOr("auto_upright", autoUpright)
		fixedRotation = config.intOr("rotation", fixedRotation)
		markerDictionary = config.stringOr("marker_dictionary", markerDictionary) ?: markerDictionary
		markerSize = config.floatOr("marker_size", markerSize)
		estimator.configure(markerDictionary, markerSize)
	}

	fun intrinsicsData(): Dictionary {
		val data = Dictionary()
		if (!intrinsicsReady) {
			return data
		}
		data["fx"] = fx
		data["fy"] = fy
		data["cx"] = cx
		data["cy"] = cy
		data["width"] = captureWidth
		data["height"] = captureHeight
		return data
	}

	// -- Ciclo di vita ---------------------------------------------------------

	fun openCamera() {
		if (camera != null) {
			return
		}
		running = true
		ensureThread()

		val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
		val selectedId = cameraId ?: findBackCameraId(manager) ?: run {
			listener.onError("nessuna fotocamera disponibile")
			return
		}
		cameraId = selectedId

		try {
			val characteristics = manager.getCameraCharacteristics(selectedId)
			readCharacteristics(characteristics)
			val size = chooseCaptureSize(characteristics)
			captureWidth = size.width
			captureHeight = size.height
			computeIntrinsics(characteristics)

			reader = ImageReader.newInstance(captureWidth, captureHeight, ImageFormat.YUV_420_888, 2)
			reader?.setOnImageAvailableListener({ r -> onImageAvailable(r) }, handler)
			manager.openCamera(selectedId, deviceCallback, handler)
		} catch (e: CameraAccessException) {
			listener.onError("CameraAccessException: ${e.message}")
		} catch (e: SecurityException) {
			listener.onError("SecurityException: ${e.message}")
		}
	}

	fun closeCamera() {
		running = false
		try {
			captureSession?.close()
		} catch (e: Exception) {
			Log.w(LOG_TAG, "closeCamera: session close failed", e)
		}
		captureSession = null
		try {
			camera?.close()
		} catch (e: Exception) {
			Log.w(LOG_TAG, "closeCamera: device close failed", e)
		}
		camera = null
		reader?.close()
		reader = null
	}

	fun stop() {
		closeCamera()
		thread?.quitSafely()
		try {
			thread?.join()
		} catch (e: InterruptedException) {
			Log.w(LOG_TAG, "stop: thread join interrupted", e)
		}
		thread = null
		handler = null
	}

	// -- Fotocamera ------------------------------------------------------------

	private fun ensureThread() {
		if (thread == null) {
			thread = HandlerThread("MarkerARCamera")
			thread?.start()
			handler = Handler(thread!!.looper)
		}
	}

	private fun findBackCameraId(manager: CameraManager): String? {
		return try {
			val ids = manager.cameraIdList
			ids.firstOrNull { id ->
				val facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
				facing == CameraCharacteristics.LENS_FACING_BACK
			} ?: ids.firstOrNull()
		} catch (e: CameraAccessException) {
			Log.e(LOG_TAG, "findBackCameraId failed", e)
			null
		}
	}

	private fun readCharacteristics(characteristics: CameraCharacteristics) {
		sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
		val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
		isFrontFacing = facing == CameraCharacteristics.LENS_FACING_FRONT
	}

	private fun chooseCaptureSize(characteristics: CameraCharacteristics): Size {
		val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
		val sizes = yuvSizes(map)
		if (sizes.isEmpty()) {
			return Size(captureWidth, captureHeight)
		}
		val requested = Size(captureWidth, captureHeight)
		sizes.firstOrNull { it == requested }?.let { return it }
		// Preferisce la dimensione >= richiesta piu' piccola, altrimenti la piu' vicina.
		val bigger = sizes
			.filter { it.width >= requested.width && it.height >= requested.height }
			.minByOrNull { it.width * it.height }
		if (bigger != null) {
			return bigger
		}
		return sizes.minByOrNull { abs(it.width * it.height - requested.width * requested.height) } ?: requested
	}

	private fun yuvSizes(map: StreamConfigurationMap?): List<Size> {
		if (map == null) {
			return emptyList()
		}
		val sizes = map.getOutputSizes(ImageFormat.YUV_420_888) ?: return emptyList()
		return sizes.filter { it.width <= 1920 && it.height <= 1080 }
	}

	private fun computeIntrinsics(characteristics: CameraCharacteristics) {
		val focal = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull() ?: 0f
		val physical = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
		if (focal > 0f && physical != null && physical.width > 0f && physical.height > 0f) {
			fx = focal.toDouble() * captureWidth / physical.width.toDouble()
			fy = focal.toDouble() * captureHeight / physical.height.toDouble()
		} else {
			// Stima prudente: FOV orizzontale ~60 gradi.
			fx = (captureWidth / 2.0) / tan(Math.toRadians(30.0))
			fy = fx
		}
		cx = captureWidth / 2.0
		cy = captureHeight / 2.0

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			val distortion = characteristics.get(CameraCharacteristics.LENS_DISTORTION)
			if (distortion != null && distortion.isNotEmpty()) {
				estimator.setDistortionCoefficients(distortion.map { it.toDouble() }.toDoubleArray())
			}
		}
		intrinsicsReady = true
		Log.i(
			LOG_TAG,
			"intrinsics: ${captureWidth}x$captureHeight fx=%.1f fy=%.1f cx=%.1f cy=%.1f sensorOrientation=%d"
				.format(fx, fy, cx, cy, sensorOrientation),
		)
	}

	private val deviceCallback = object : CameraDevice.StateCallback() {
		override fun onOpened(device: CameraDevice) {
			Log.d(LOG_TAG, "camera opened")
			camera = device
			createCaptureSession()
		}

		override fun onDisconnected(device: CameraDevice) {
			Log.w(LOG_TAG, "camera disconnected")
			device.close()
			camera = null
		}

		override fun onError(device: CameraDevice, error: Int) {
			device.close()
			camera = null
			listener.onError("camera error: $error")
		}
	}

	private fun createCaptureSession() {
		val device = camera ?: return
		val surface = reader?.surface ?: return
		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
				val executor = Executor { command -> handler?.post(command) }
				val configuration = SessionConfiguration(
					SessionConfiguration.SESSION_REGULAR,
					Collections.singletonList(android.hardware.camera2.params.OutputConfiguration(surface)),
					executor,
					sessionCallback,
				)
				device.createCaptureSession(configuration)
			} else {
				@Suppress("DEPRECATION")
				device.createCaptureSession(Collections.singletonList(surface), sessionCallback, handler)
			}
		} catch (e: CameraAccessException) {
			listener.onError("createCaptureSession failed: ${e.message}")
		}
	}

	private val sessionCallback = object : CameraCaptureSession.StateCallback() {
		override fun onConfigured(session: CameraCaptureSession) {
			captureSession = session
			val device = camera ?: return
			val surface = reader?.surface ?: return
			try {
				val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
				request.addTarget(surface)
				request.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
				session.setRepeatingRequest(request.build(), null, handler)
			} catch (e: CameraAccessException) {
				listener.onError("setRepeatingRequest failed: ${e.message}")
			}
		}

		override fun onConfigureFailed(session: CameraCaptureSession) {
			listener.onError("capture session configuration failed")
		}
	}

	// -- Elaborazione frame ----------------------------------------------------

	private fun onImageAvailable(imageReader: ImageReader) {
		if (!running) {
			return
		}
		val image: Image = try {
			imageReader.acquireLatestImage()
		} catch (e: IllegalStateException) {
			null
		} ?: return

		try {
			frameCounter++
			val rotation = if (autoUpright) computeUprightRotation() else fixedRotation
			if (frameCounter % previewEvery == 0) {
				emitPreviewFrame(image, rotation)
			}
			if (frameCounter % detectEvery == 0) {
				emitDetection(image, rotation)
			}
		} catch (e: Throwable) {
			Log.e(LOG_TAG, "frame processing failed", e)
		} finally {
			image.close()
		}
	}

	private fun emitPreviewFrame(image: Image, rotation: Int) {
		val rgba = FrameTransforms.yuvToRgba(image, captureWidth, captureHeight)
		val rotated = FrameTransforms.rotateRgba(rgba, captureWidth, captureHeight, rotation)

		// Le dimensioni richieste sono intese per l'anteprima ruotata: se
		// l'orientamento non combacia (es. sensore orizzontale senza rotazione)
		// vengono scambiate per non deformare l'immagine.
		var finalWidth = if (previewWidth > 0) previewWidth else rotated.width
		var finalHeight = if (previewHeight > 0) previewHeight else rotated.height
		if ((rotated.width > rotated.height) != (finalWidth > finalHeight)) {
			val swap = finalWidth
			finalWidth = finalHeight
			finalHeight = swap
		}
		val data = if (finalWidth != rotated.width || finalHeight != rotated.height) {
			FrameTransforms.scaleRgba(rotated.data, rotated.width, rotated.height, finalWidth, finalHeight)
		} else {
			rotated.data
		}

		val frame = Dictionary()
		frame["data"] = data
		frame["width"] = finalWidth
		frame["height"] = finalHeight
		frame["rotation"] = rotation

		// Intrinsics upright, riscalate sui pixel dell'anteprima emessa.
		val upright = uprightIntrinsics(rotation)
		val scale = finalHeight.toDouble() / uprightHeight(rotation).toDouble()
		frame["fx"] = upright.first * scale
		frame["fy"] = upright.second * scale
		frame["cx"] = finalWidth / 2.0
		frame["cy"] = finalHeight / 2.0

		listener.onPreviewFrame(frame)
	}

	private fun emitDetection(image: Image, rotation: Int) {
		if (!intrinsicsReady) {
			return
		}
		val gray = FrameTransforms.yPlaneToGray(image, captureWidth, captureHeight)
		val poses = estimator.detect(gray, captureWidth, captureHeight, fx, fy, cx, cy, rotation.toDouble())

		val data = Dictionary()
		data["count"] = poses.size
		if (poses.isNotEmpty()) {
			val best = poses.first()
			data["id"] = best.id
			data["pose"] = best.values
		} else {
			data["id"] = -1
			data["pose"] = FloatArray(12)
		}
		listener.onMarkersDetected(data)
	}

	/** fx, fy dopo la rotazione (scambiati per 90/270). */
	private fun uprightIntrinsics(rotation: Int): Pair<Double, Double> {
		val normalized = ((rotation % 360) + 360) % 360
		return if (normalized == 90 || normalized == 270) {
			Pair(fy, fx)
		} else {
			Pair(fx, fy)
		}
	}

	private fun uprightHeight(rotation: Int): Int {
		val normalized = ((rotation % 360) + 360) % 360
		return if (normalized == 90 || normalized == 270) captureWidth else captureHeight
	}

	private fun computeUprightRotation(): Int {
		val surfaceRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
			activity.display?.rotation ?: Surface.ROTATION_0
		} else {
			@Suppress("DEPRECATION")
			(activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.rotation
		}
		val deviceDegrees = when (surfaceRotation) {
			Surface.ROTATION_90 -> 90
			Surface.ROTATION_180 -> 180
			Surface.ROTATION_270 -> 270
			else -> 0
		}
		return if (isFrontFacing) {
			(sensorOrientation + deviceDegrees + 360) % 360
		} else {
			(sensorOrientation - deviceDegrees + 360) % 360
		}
	}
}

// -- Helper di lettura della config -------------------------------------------

private fun Dictionary.intOr(key: String, fallback: Int): Int =
	(this[key] as? Number)?.toInt() ?: fallback

private fun Dictionary.floatOr(key: String, fallback: Double): Double =
	(this[key] as? Number)?.toDouble() ?: fallback

private fun Dictionary.boolOr(key: String, fallback: Boolean): Boolean =
	(this[key] as? Boolean) ?: fallback

private fun Dictionary.stringOr(key: String, fallback: String?): String? =
	(this[key] as? String) ?: fallback
