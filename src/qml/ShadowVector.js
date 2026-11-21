// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

.pragma library

// Legacy configurations store the light source as an integer X/Y vector.
// The optional angle stores the shadow direction in screen coordinates
// (clockwise, +Y down). When present, preserve the old vector's magnitude and
// rotate it to the exact user-selected direction. A negative angle keeps the
// legacy vector untouched.
function lightX(lightX, lightY, shadowDirectionAngle) {
    if (shadowDirectionAngle < 0)
        return lightX
    const distance = Math.hypot(lightX, lightY)
    return -distance * Math.cos(shadowDirectionAngle * Math.PI / 180)
}

function lightY(lightX, lightY, shadowDirectionAngle) {
    if (shadowDirectionAngle < 0)
        return lightY
    const distance = Math.hypot(lightX, lightY)
    return -distance * Math.sin(shadowDirectionAngle * Math.PI / 180)
}
