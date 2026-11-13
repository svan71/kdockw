// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <numbers>
#include <vector>

namespace kdockw
{

/// Default Gaussian spread of the zoom curve, as a multiple of the icon size.
inline constexpr double kDefaultZoomSigmaFactor = 1.2;

/// Compute the parabolic zoom factor of one icon using a Gaussian curve:
/// 1 + (maxZoomFactor - 1) * exp(-(distance / sigma)^2), sigma = iconSize * sigmaFactor.
/// @param distance Distance from mouse to icon center (pixels)
/// @param iconSize Base icon size (pixels)
/// @param maxZoomFactor Maximum zoom multiplier (e.g. 1.6)
/// @param sigmaFactor Gaussian spread as a multiple of @p iconSize
/// @return Zoom factor in range [1.0, maxZoomFactor]
[[nodiscard]] inline double parabolicZoomFactor(double distance, double iconSize, double maxZoomFactor, double sigmaFactor = kDefaultZoomSigmaFactor)
{
    const double sigma = iconSize * sigmaFactor;
    if (maxZoomFactor <= 1.0 || sigma <= 0.0) {
        return 1.0;
    }
    return 1.0 + (maxZoomFactor - 1.0) * std::exp(-(distance * distance) / (sigma * sigma));
}

/// How magnified dock icons make room.
enum class ZoomStyle : int {
    /// macOS-style: icons magnify along the Gaussian curve and push their
    /// neighbours aside; the background grows by the total extra width.
    Parabolic = 0,
    /// Icons scale in place with the Gaussian curve; nothing moves.
    InPlace = 1,
};

/// Zoomed layout of a row of dock items along the dock's primary axis.
struct DockZoomLayout {
    std::vector<double> scales; ///< Per-item visual zoom factor, each >= 1
    std::vector<double> offsets; ///< Per-item translation of the icon centre from its rest centre
    double leadingGrowth = 0.0; ///< Background extension before its rest leading edge (>= 0)
    double trailingGrowth = 0.0; ///< Background extension after its rest trailing edge (>= 0)
};

/// Compute the zoom layout of @p count equally sized dock items for one cursor
/// position.
///
/// All coordinates share one rest frame on the primary axis: item i rests at
/// [restStart + i * pitch + boundaryGap (when i >= boundary), restStart + i * pitch
/// + boundaryGap (when i >= boundary) + iconSize] with pitch = iconSize + spacing,
/// and its rest centre is the corresponding slot centre. The cursor is expressed
/// in that same rest frame. restBackgroundStart/restBackgroundEnd are the
/// background's rest edges and [minEdge, maxEdge] the surface bounds the
/// background must not cross (pass -Infinity/Infinity for no bound).
///
/// The optional-looking boundary is deliberately required: pass -1 and 0 when
/// no pinned/running boundary is present. When boundary >= 0, boundaryGap is a
/// fixed, unscaled increment inserted before item boundary and included in the
/// row extent.
///
/// Both styles scale item i by z_i = parabolicZoomFactor(c_i - cursor,
/// iconSize, M) (Gaussian, sigma = 1.2 * iconSize).
///
/// InPlace: offsets and growth stay 0 and the bounds are ignored.
///
/// Parabolic: the zoomed icons are laid out edge to edge with the unscaled
/// gap, so the row grows by G = sum(iconSize * (z_i - 1)). That growth is
/// split between the two ends in proportion to how much of the Gaussian bump
/// lies over the row on each side of the cursor:
///   a = erf(max(0, cursor - rowStart) / sigma), b = erf(max(0, rowEnd - cursor) / sigma)
///   leadingGrowth = G * a / (a + b), trailingGrowth = G - leadingGrowth
/// where [rowStart, rowEnd) spans every item's slot (icon plus half a gap on
/// each side), including the fixed boundary gap. Away from the ends a = b = 1,
/// so each end grows by exactly G/2 and, because the sampled Gaussian sum G is
/// constant there, both background edges and every far icon stay still while
/// the cursor moves.
///
/// Toward an end the growth shifts smoothly to that end. Pinning the icon under
/// the cursor to the cursor (Plank, Apple's patent) makes the whole row shake
/// back and forth once per icon.
///
/// When G exceeds the slack between the background's rest edges and the bounds,
/// the positional growth is reduced to fit (each item's positional width becomes
/// iconSize + (iconSize * z_i - iconSize) * slack / G) while the visual scales
/// stay full, so neighbours overlap slightly instead of the zoom disappearing.
/// Each end's growth is clamped to its own slack. The fixed boundary gap is
/// never scaled or compressed.
///
/// @param count Number of items
/// @param restStart Leading edge of item 0 at rest
/// @param iconSize Base icon size
/// @param spacing Gap between adjacent icons
/// @param boundary Index of first item in the second zone, or -1 when absent
/// @param boundaryGap Fixed extra gap inserted before @p boundary
/// @param restBackgroundStart Background's rest leading edge
/// @param restBackgroundEnd Background's rest trailing edge
/// @param maxZoomFactor Zoom factor at the cursor (M)
/// @param style Room-making strategy
/// @param active false yields the rest layout (pointer not over the dock)
/// @param cursor Cursor position in the rest frame
/// @param minEdge Lowest allowed leading edge of the grown background
/// @param maxEdge Highest allowed trailing edge of the grown background
[[nodiscard]] inline DockZoomLayout computeDockZoomItems(const std::vector<double> &extents,
                                                    const std::vector<bool> &canMagnify,
                                                    double restStart,
                                                    double spacing,
                                                    int boundary,
                                                    double boundaryGap,
                                                    double restBackgroundStart,
                                                    double restBackgroundEnd,
                                                    double maxZoomFactor,
                                                    ZoomStyle style,
                                                    bool active,
                                                    double cursor,
                                                    double minEdge,
                                                    double maxEdge)
{
    DockZoomLayout layout;
    const std::size_t n = extents.size();
    if (n == 0) return layout;
    layout.scales.assign(n, 1.0);
    layout.offsets.assign(n, 0.0);
    const bool hasBoundary = boundary >= 0 && static_cast<std::size_t>(boundary) < n && boundaryGap > 0.0;
    std::vector<double> centres(n);
    double edge = restStart;
    double rowEnd = restStart;
    for (std::size_t i = 0; i < n; ++i) {
        if (hasBoundary && static_cast<int>(i) == boundary) edge += boundaryGap;
        centres[i] = edge + extents[i] * 0.5;
        edge += extents[i] + spacing;
        rowEnd = edge;
    }
    if (!active || maxZoomFactor <= 1.0) return layout;
    for (std::size_t i = 0; i < n; ++i) {
        if (i < canMagnify.size() && canMagnify[i])
            layout.scales[i] = parabolicZoomFactor(centres[i] - cursor, extents[i], maxZoomFactor);
    }
    if (style == ZoomStyle::InPlace) return layout;

    double growth = 0.0;
    double referenceSize = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (i < canMagnify.size() && canMagnify[i]) {
            growth += extents[i] * (layout.scales[i] - 1.0);
            referenceSize = std::max(referenceSize, extents[i]);
        }
    }
    if (growth <= 0.0) return layout;
    const double sigma = std::max(1.0, referenceSize * kDefaultZoomSigmaFactor);
    const double rowStart = restStart - spacing * 0.5;
    rowEnd -= spacing * 0.5;
    const double before = std::erf(std::max(0.0, cursor - rowStart) / sigma);
    const double after = std::erf(std::max(0.0, rowEnd - cursor) / sigma);
    const double leadingShare = before + after > 0.0 ? before / (before + after) : 0.5;
    const double roomL = std::max(0.0, restBackgroundStart - minEdge);
    const double roomR = std::max(0.0, maxEdge - restBackgroundEnd);
    const double fitted = std::min(growth, roomL + roomR);
    const double leading = std::clamp(fitted * leadingShare, fitted - roomR, roomL);
    const double positionalShare = fitted / growth;
    edge = restStart - leading;
    for (std::size_t i = 0; i < n; ++i) {
        if (hasBoundary && static_cast<int>(i) == boundary) edge += boundaryGap;
        const double width = extents[i] + extents[i] * (layout.scales[i] - 1.0) * positionalShare;
        layout.offsets[i] = edge + width * 0.5 - centres[i];
        edge += width + spacing;
    }
    layout.leadingGrowth = leading;
    layout.trailingGrowth = fitted - leading;
    return layout;
}

[[nodiscard]] inline DockZoomLayout computeDockZoom(int count,
                                                    double restStart,
                                                    double iconSize,
                                                    double spacing,
                                                    int boundary,
                                                    double boundaryGap,
                                                    double restBackgroundStart,
                                                    double restBackgroundEnd,
                                                    double maxZoomFactor,
                                                    ZoomStyle style,
                                                    bool active,
                                                    double cursor,
                                                    double minEdge,
                                                    double maxEdge)
{
    if (count <= 0 || iconSize <= 0.0) return {};
    const auto n = static_cast<std::size_t>(count);
    return computeDockZoomItems(std::vector<double>(n, iconSize), std::vector<bool>(n, true), restStart, spacing,
                                boundary, boundaryGap, restBackgroundStart, restBackgroundEnd, maxZoomFactor,
                                style, active, cursor, minEdge, maxEdge);
}

} // namespace kdockw
