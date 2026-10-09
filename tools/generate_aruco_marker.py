#!/usr/bin/env python3
"""Genera il marker ArUco usato dal backend marker.

Requisiti: pip install opencv-python-headless (oppure opencv-python).

Uso:
    python3 tools/generate_aruco_marker.py [output.png]

Genera un marker DICT_4X4_50 id 0 con quiet zone bianca. Per usarlo:
stampare l'immagine in modo che il quadrato nero misuri 12 cm di lato
(l'immagine intera risulta ~15 cm di lato, quiet zone inclusa).
Se il lato stampato cambia, aggiornare MARKER_SIZE_METERS in
ar-camera_godot/scripts/ar/backends/ar_backend_marker.gd.
"""

import os
import sys

import cv2
import numpy as np

SIDE_PX = 1000  # lato totale dell'immagine
QUIET_ZONE = 0.125  # frazione di quiet zone per lato
MARKER_ID = 0
DICTIONARY = cv2.aruco.DICT_4X4_50


def main() -> None:
    output = sys.argv[1] if len(sys.argv) > 1 else (
        "ar-camera_godot/assets/markers/aruco_4x4_50_id0.png"
    )
    dictionary = cv2.aruco.getPredefinedDictionary(DICTIONARY)
    marker_px = int(SIDE_PX * (1 - 2 * QUIET_ZONE))
    marker = cv2.aruco.generateImageMarker(dictionary, MARKER_ID, marker_px)
    margin = (SIDE_PX - marker_px) // 2
    canvas = np.full((SIDE_PX, SIDE_PX), 255, dtype=np.uint8)
    canvas[margin : margin + marker_px, margin : margin + marker_px] = marker
    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    if not cv2.imwrite(output, canvas):
        raise SystemExit(f"impossibile scrivere {output}")
    print(f"scritto {output}: id {MARKER_ID}, quadrato nero {marker_px}px su {SIDE_PX}px")


if __name__ == "__main__":
    main()
