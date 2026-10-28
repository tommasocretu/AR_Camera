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
		return readPlane(image.planes[0], width, height)
	}

	/**
	 * Copia un piano di [Image] in un ByteArray tightly packed, gestendo
	 * row stride e pixel stride di YUV_420_888.
	 */
	private fun readPlane(plane: Image.Plane, width: Int, height: Int): ByteArray {
		val buffer = plane.buffer
		val rowStride = plane.rowStride
		val pixelStride = plane.pixelStride
		// La posizione iniziale del buffer e' l'inizio del piano: per i piani
		// U/V interleaved puo' essere diversa da zero.
		val base = buffer.position()
		val output = ByteArray(width * height)
		if (pixelStride == 1 && rowStride >= width) {
			if (rowStride == width) {
				buffer.position(base)
				buffer.get(output, 0, width * height)
			} else {
				for (y in 0 until height) {
					buffer.position(base + y * rowStride)
					buffer.get(output, y * width, width)
				}
			}
			return output
		}
		var offset = 0
		for (y in 0 until height) {
			val rowStart = base + y * rowStride
			for (x in 0 until width) {
				output[offset++] = buffer.get(rowStart + x * pixelStride)
			}
		}
		return output
	}

	/** Converte un frame YUV_420_888 in RGBA8 tightly packed. */
	fun yuvToRgba(image: Image, width: Int, height: Int): ByteArray {
		val chromaWidth = width / 2
		val chromaHeight = height / 2
		val yBytes = readPlane(image.planes[0], width, height)
		val uBytes = readPlane(image.planes[1], chromaWidth, chromaHeight)
		val vBytes = readPlane(image.planes[2], chromaWidth, chromaHeight)

		val output = ByteArray(width * height * 4)
		var offset = 0

		for (y in 0 until height) {
			val yRow = y * width
			val uvRow = (y / 2) * chromaWidth

			for (x in 0 until width) {
				val yVal = yBytes[yRow + x].toInt() and 0xFF
				val uvCol = x / 2
				val uVal = (uBytes[uvRow + uvCol].toInt() and 0xFF) - 128
				val vVal = (vBytes[uvRow + uvCol].toInt() and 0xFF) - 128

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
