package org.tommasocretu.markerar

import org.opencv.calib3d.Calib3d
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.core.MatOfPoint2f
import org.opencv.core.MatOfPoint3f
import org.opencv.core.Point3
import org.opencv.objdetect.ArucoDetector
import org.opencv.objdetect.DetectorParameters
import org.opencv.objdetect.Objdetect
import kotlin.math.cos
import kotlin.math.sin

/**
 * Posa di un marker in coordinate Godot: 12 float (colonne del basis + origine),
 * pronti per costruire un Transform3D lato GDScript.
 */
internal data class GodotPose(val id: Int, val values: FloatArray)

/**
 * Rilevamento marker ArUco e stima della posa con OpenCV.
 *
 * Convenzioni:
 *  - OpenCV: X a destra, Y in basso, Z in avanti (frame della camera).
 *  - Godot: X a destra, Y in alto, Z indietro.
 *
 * I punti oggetto definiscono il frame del marker con Y verso l'alto e Z
 * uscente dal piano (verso la camera), cioe' lo stesso orientamento fisico
 * del frame Godot a identita'. La conversione e' quindi R_godot = M * R_cv e
 * t_godot = M * t_cv con M = diag(1, -1, -1) (rotazione di 180 gradi su X).
 *
 * Il frame di input e' quello grezzo del sensore (non ruotato): la rotazione
 * applicata per rendere il frame upright viene compensata ruotando la posa di
 * Rz(rotazione) prima della conversione (una rotazione oraria dell'immagine
 * equivale a ruotare il frame camera di +rotazione attorno all'asse ottico).
 */
internal class ArucoPoseEstimator {

	companion object {
		const val DEFAULT_DICTIONARY_NAME = "DICT_4X4_50"

		private val DICTIONARIES = mapOf(
			"DICT_4X4_50" to Objdetect.DICT_4X4_50,
			"DICT_5X5_50" to Objdetect.DICT_5X5_50,
			"DICT_6X6_50" to Objdetect.DICT_6X6_50,
			"DICT_ARUCO_ORIGINAL" to Objdetect.DICT_ARUCO_ORIGINAL,
		)

		fun dictionaryNames(): Array<String> = DICTIONARIES.keys.toTypedArray()
	}

	private var dictionaryName = DEFAULT_DICTIONARY_NAME
	private var markerSize = 0.12
	private var detector: ArucoDetector? = null

	private val objectPoints = MatOfPoint3f()
	private val cameraMatrix = Mat(3, 3, CvType.CV_64F)
	private val distortion = MatOfDouble(0.0, 0.0, 0.0, 0.0, 0.0)
	private val rvec = Mat()
	private val tvec = Mat()
	private val rotation = Mat()
	private val gray = Mat()

	fun configure(dictionary: String, markerSizeMeters: Double) {
		if (markerSizeMeters > 0.0) {
			markerSize = markerSizeMeters
		}
		val resolved = if (DICTIONARIES.containsKey(dictionary)) dictionary else DEFAULT_DICTIONARY_NAME
		if (resolved != dictionaryName || detector == null) {
			dictionaryName = resolved
			detector = ArucoDetector(
				Objdetect.getPredefinedDictionary(DICTIONARIES.getValue(resolved)),
				DetectorParameters(),
			)
		}
		updateObjectPoints()
	}

	fun setDistortionCoefficients(coefficients: DoubleArray) {
		if (coefficients.size >= 4) {
			distortion.fromArray(*coefficients)
		} else {
			distortion.fromArray(0.0, 0.0, 0.0, 0.0, 0.0)
		}
	}

	/**
	 * Rileva i marker in [grayBytes] (frame grezzo del sensore, non ruotato) e
	 * restituisce le pose in coordinate Godot.
	 *
	 * @param frameRotationDegrees rotazione oraria applicata al frame per
	 *   renderlo upright; viene compensata sulla posa.
	 */
	fun detect(
		grayBytes: ByteArray,
		width: Int,
		height: Int,
		fx: Double,
		fy: Double,
		cx: Double,
		cy: Double,
		frameRotationDegrees: Double,
	): List<GodotPose> {
		val aruco = detector ?: return emptyList()
		if (width <= 0 || height <= 0 || grayBytes.size < width * height) {
			return emptyList()
		}

		gray.create(height, width, CvType.CV_8UC1)
		gray.put(0, 0, grayBytes)
		cameraMatrix.put(0, 0, fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0)

		val corners = ArrayList<Mat>()
		val ids = Mat()
		val rejected = ArrayList<Mat>()
		aruco.detectMarkers(gray, corners, ids, rejected)
		if (ids.empty() || corners.isEmpty()) {
			return emptyList()
		}

		val idValues = IntArray(ids.total().toInt())
		ids.get(0, 0, idValues)

		val poses = ArrayList<GodotPose>(corners.size)
		for (i in corners.indices) {
			val imagePoints = MatOfPoint2f(corners[i])
			val solved = Calib3d.solvePnP(objectPoints, imagePoints, cameraMatrix, distortion, rvec, tvec)
			if (!solved) {
				continue
			}
			Calib3d.Rodrigues(rvec, rotation)

			val rotationValues = DoubleArray(9)
			rotation.get(0, 0, rotationValues)
			val translation = DoubleArray(3)
			tvec.get(0, 0, translation)

			val markerId = if (i < idValues.size) idValues[i] else -1
			poses.add(
				GodotPose(markerId, toGodotPose(rotationValues, translation, frameRotationDegrees)),
			)
		}
		return poses
	}

	private fun updateObjectPoints() {
		val half = markerSize / 2.0
		objectPoints.fromArray(
			Point3(-half, half, 0.0), // angolo 0: alto-sinistra
			Point3(half, half, 0.0), // angolo 1: alto-destra
			Point3(half, -half, 0.0), // angolo 2: basso-destra
			Point3(-half, -half, 0.0), // angolo 3: basso-sinistra
		)
	}

	private fun toGodotPose(rotationValues: DoubleArray, translation: DoubleArray, frameRotationDegrees: Double): FloatArray {
		val theta = Math.toRadians(frameRotationDegrees)
		val c = cos(theta)
		val s = sin(theta)

		// R_rot = Rz(theta) * R
		val r = DoubleArray(9)
		for (col in 0 until 3) {
			val x = rotationValues[col]
			val y = rotationValues[3 + col]
			val z = rotationValues[6 + col]
			r[col] = c * x - s * y
			r[3 + col] = s * x + c * y
			r[6 + col] = z
		}

		// t_rot = Rz(theta) * t
		val tx = c * translation[0] - s * translation[1]
		val ty = s * translation[0] + c * translation[1]
		val tz = translation[2]

		// M = diag(1, -1, -1): nega la seconda e la terza riga di R e y/z di t.
		// Colonne del basis Godot + origine.
		return floatArrayOf(
			r[0].toFloat(), (-r[3]).toFloat(), (-r[6]).toFloat(),
			r[1].toFloat(), (-r[4]).toFloat(), (-r[7]).toFloat(),
			r[2].toFloat(), (-r[5]).toFloat(), (-r[8]).toFloat(),
			tx.toFloat(), (-ty).toFloat(), (-tz).toFloat(),
		)
	}
}
