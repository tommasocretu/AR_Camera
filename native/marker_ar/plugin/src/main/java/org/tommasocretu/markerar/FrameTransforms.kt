package org.tommasocretu.markerar

import android.media.Image

/**
 * Buffer immagine con dimensioni, usato per i frame elaborati.
 * I dati sono sempre tightly packed (nessun row stride).
 */
internal class ImageBuffer(val data: ByteArray, val width: Int, val height: Int)

/**
 * Trasformazioni dei frame YUV_420_888 di Camera2.
 *
 * Adattato (MIT) da godot-mobile-plugins/godot-native-camera:
 * https://github.com/godot-mobile-plugins/godot-native-camera
 */
internal object FrameTransforms {

	/** Estrae il piano Y come immagine grayscale tightly packed. */
	fun yPlaneToGray(image: Image, width: Int, height: Int): ByteArray {
		val yPlane = image.planes[0]
		val yBuffer = yPlane.buffer
		val yRowStride = yPlane.rowStride
		val yPixelStride = yPlane.pixelStride
		val output = ByteArray(width * height)
		if (yPixelStride == 1 && yRowStride == width) {
			yBuffer.get(output, 0, width * height)
		} else {
			var offset = 0
			for (y in 0 until height) {
				val rowStart = y * yRowStride
				for (x in 0 until width) {
					output[offset++] = yBuffer.get(rowStart + x * yPixelStride)
				}
			}
		}
		return output
	}

	/** Converte un frame YUV_420_888 in RGBA8 tightly packed. */
	fun yuvToRgba(image: Image, width: Int, height: Int): ByteArray {
		val yPlane = image.planes[0]
		val uPlane = image.planes[1]
		val vPlane = image.planes[2]

		val yBuffer = yPlane.buffer
		val uBuffer = uPlane.buffer
		val vBuffer = vPlane.buffer

		val yRowStride = yPlane.rowStride
		val uRowStride = uPlane.rowStride
		val vRowStride = vPlane.rowStride
		val yPixelStride = yPlane.pixelStride
		val uPixelStride = uPlane.pixelStride
		val vPixelStride = vPlane.pixelStride

		val output = ByteArray(width * height * 4)
		var offset = 0

		for (y in 0 until height) {
			val yRowStart = y * yRowStride
			val uRowStart = (y / 2) * uRowStride
			val vRowStart = (y / 2) * vRowStride

			for (x in 0 until width) {
				val yVal = yBuffer.get(yRowStart + x * yPixelStride).toInt() and 0xFF

				val uvCol = (x / 2)
				val uVal = (uBuffer.get(uRowStart + uvCol * uPixelStride).toInt() and 0xFF) - 128
				val vVal = (vBuffer.get(vRowStart + uvCol * vPixelStride).toInt() and 0xFF) - 128

				val r = yVal + 1.402f * vVal
				val g = yVal - 0.34414f * uVal - 0.71414f * vVal
				val b = yVal + 1.772f * uVal

				output[offset++] = clampToByte(r)
				output[offset++] = clampToByte(g)
				output[offset++] = clampToByte(b)
				output[offset++] = 0xFF.toByte()
			}
		}
		return output
	}

	/**
	 * Ruota un frame RGBA8 in senso orario di [rotation] gradi
	 * (0, 90, 180 o 270). Le dimensioni vengono scambiate per 90/270.
	 */
	fun rotateRgba(src: ByteArray, width: Int, height: Int, rotation: Int): ImageBuffer {
		val normalized = ((rotation % 360) + 360) % 360
		if (normalized == 0) {
			return ImageBuffer(src, width, height)
		}
		val newWidth = if (normalized == 90 || normalized == 270) height else width
		val newHeight = if (normalized == 90 || normalized == 270) width else height
		val dst = ByteArray(src.size)

		for (y in 0 until height) {
			for (x in 0 until width) {
				val srcIndex = (y * width + x) * 4
				val (dx, dy) = when (normalized) {
					90 -> Pair(height - 1 - y, x)
					180 -> Pair(width - 1 - x, height - 1 - y)
					else -> Pair(y, width - 1 - x)
				}
				val dstIndex = (dy * newWidth + dx) * 4
				dst[dstIndex] = src[srcIndex]
				dst[dstIndex + 1] = src[srcIndex + 1]
				dst[dstIndex + 2] = src[srcIndex + 2]
				dst[dstIndex + 3] = src[srcIndex + 3]
			}
		}
		return ImageBuffer(dst, newWidth, newHeight)
	}

	/** Ridimensiona un frame RGBA8 con interpolazione nearest-neighbour. */
	fun scaleRgba(src: ByteArray, srcWidth: Int, srcHeight: Int, dstWidth: Int, dstHeight: Int): ByteArray {
		val dst = ByteArray(dstWidth * dstHeight * 4)
		for (dy in 0 until dstHeight) {
			val sy = dy * srcHeight / dstHeight
			for (dx in 0 until dstWidth) {
				val sx = dx * srcWidth / dstWidth
				val srcIndex = (sy * srcWidth + sx) * 4
				val dstIndex = (dy * dstWidth + dx) * 4
				dst[dstIndex] = src[srcIndex]
				dst[dstIndex + 1] = src[srcIndex + 1]
				dst[dstIndex + 2] = src[srcIndex + 2]
				dst[dstIndex + 3] = src[srcIndex + 3]
			}
		}
		return dst
	}

	private fun clampToByte(value: Float): Byte {
		val clamped = if (value < 0f) 0 else if (value > 255f) 255 else value.toInt()
		return clamped.toByte()
	}
}
