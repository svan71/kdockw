// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "models/mediaartworkitem.h"

#include <catch2/catch_test_macros.hpp>

TEST_CASE("MPRIS artwork rejects unsupported URL schemes and clears stale imagery", "[media-player][artwork]")
{
    kdockw::MediaArtworkItem artwork;
    artwork.setSource(QUrl(QStringLiteral("data:image/svg+xml,<svg/>")));
    CHECK(artwork.source().scheme() == QStringLiteral("data"));
    CHECK_FALSE(artwork.ready());
    artwork.setSource(QUrl(QStringLiteral("file:///definitely-not-a-media-artwork.png")));
    CHECK_FALSE(artwork.ready());
    artwork.setSource({});
    CHECK(artwork.source().isEmpty());
    CHECK_FALSE(artwork.ready());
}
