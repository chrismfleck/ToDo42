#!/usr/bin/env python3
"""Mirrors ShareExtension PageMetadata image / Instagram embed helpers."""

import re
import sys
from html import unescape
from urllib.parse import urlparse


def first_match(pattern, text, group):
    match = re.search(pattern, text, flags=re.IGNORECASE | re.DOTALL)
    if not match or match.lastindex is None or match.lastindex < group:
        if match and group == 0:
            return match.group(0)
        if match and group <= len(match.groups()):
            return match.group(group)
        return None
    return match.group(group)


def looks_like_logo(url):
    lower = url.lower()
    if "favicon" in lower:
        return True
    if "apple-touch-icon" in lower:
        return True
    if "/static/" in lower and ("/images/" in lower or "/rsrc" in lower or "/ico/" in lower):
        return True
    if "logo" in lower and ("instagram" in lower or "facebook" in lower or "tiktok" in lower):
        return True
    if ("tiktokcdn" in lower or "muscdn" in lower) and (
        "static" in lower or ".js" in lower or ".css" in lower or "obj/tiktok-web" in lower
    ):
        return True
    return False


def decode_html(value):
    return unescape(value).replace("\\/", "/")


def meta(html, *, property=None, name=None, itemprop=None):
    key = property or name or itemprop or ""
    attribute = "property" if property else ("itemprop" if itemprop else "name")
    key_re = re.escape(key)
    patterns = [
        rf'{attribute}\s*=\s*["\']{key_re}["\'][^>]*content\s*=\s*["\']([^"\']+)["\']',
        rf'content\s*=\s*["\']([^"\']+)["\'][^>]*{attribute}\s*=\s*["\']{key_re}["\']',
    ]
    for pattern in patterns:
        value = first_match(pattern, html, 1)
        if value:
            return decode_html(value)
    return None


def json_ld_string(html, key):
    block = first_match(r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', html, 1)
    if not block:
        return None
    quoted = first_match(rf'"{key}"\s*:\s*"([^"]+)"', block, 1)
    if quoted:
        return decode_html(quoted)
    nested = first_match(rf'"{key}"\s*:\s*\{{\s*"url"\s*:\s*"([^"]+)"', block, 1)
    if nested:
        return decode_html(nested)
    array_first = first_match(rf'"{key}"\s*:\s*\[\s*"([^"]+)"', block, 1)
    if array_first:
        return decode_html(array_first)
    return None


def image_candidates(html):
    found = []

    def add(value):
        if not value:
            return
        trimmed = decode_html(value).strip()
        if not trimmed or trimmed in found:
            return
        if looks_like_logo(trimmed):
            return
        found.append(trimmed)

    add(meta(html, property="og:image"))
    add(meta(html, property="og:image:secure_url"))
    add(meta(html, property="og:image:url"))
    add(meta(html, property="og:video:poster"))
    add(meta(html, name="twitter:image"))
    add(meta(html, name="twitter:image:src"))
    add(meta(html, itemprop="image"))
    add(json_ld_string(html, "image"))
    add(json_ld_string(html, "thumbnailUrl"))
    cover = first_match(r'"(?:originCover|dynamicCover|cover|thumbnail_url)"\s*:\s*"(https?://[^"]+)"', html, 1)
    add(cover)
    href = first_match(r'<link[^>]+rel\s*=\s*["\']image_src["\'][^>]+href\s*=\s*["\']([^"\']+)["\']', html, 1)
    add(href)
    href = first_match(r'<link[^>]+href\s*=\s*["\']([^"\']+)["\'][^>]+rel\s*=\s*["\']image_src["\']', html, 1)
    add(href)
    cdn = first_match(
        r'https?://[^"\'\\\s]+(?:cdninstagram\.com|fbcdn\.net|scontent)[^"\'\\\s]+\.(?:jpe?g|png|webp)',
        html,
        0,
    )
    add(cdn)
    return found


def is_tiktok_url(string):
    return "tiktok.com" in string.lower()


def oembed_url(page_url):
    from urllib.parse import urlencode
    return "https://www.tiktok.com/oembed?" + urlencode({"url": page_url})


def instagram_embed_url(url):
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if "instagram.com" not in host and "instagr.am" not in host:
        return None
    pattern = r"/(p|reel|reels|tv)/([A-Za-z0-9_-]+)"
    kind = first_match(pattern, parsed.path, 1)
    code = first_match(pattern, parsed.path, 2)
    if not kind or not code:
        return None
    if kind.lower() == "reels":
        kind = "reel"
    return f"https://www.instagram.com/{kind.lower()}/{code}/embed/"


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    html = """
    <html><head>
    <meta property="og:image" content="https://cdn.example.com/photo.jpg">
    <meta name="twitter:image" content="https://cdn.example.com/tw.jpg">
    <link rel="image_src" href="/relative.png">
    <script type="application/ld+json">
    {"image":{"url":"https:\\/\\/scontent.cdninstagram.com\\/v\\/t51.123\\/abc.jpg"}}
    </script>
    </head></html>
    """
    found = image_candidates(html)
    check(found[0] == "https://cdn.example.com/photo.jpg", f"og:image first, got {found}")
    check("https://cdn.example.com/tw.jpg" in found, f"twitter image missing: {found}")
    check("/relative.png" in found, f"image_src missing: {found}")
    check(
        "https://scontent.cdninstagram.com/v/t51.123/abc.jpg" in found,
        f"json-ld escaped url missing: {found}",
    )

    content_first = '<meta content="https://img.example/a.jpg" property="og:image">'
    check(image_candidates(content_first) == ["https://img.example/a.jpg"], "content-first og:image")

    login_wall = """
    <meta property="og:image" content="https://static.cdninstagram.com/rsrc.php/v3/yI/r/favicon.ico">
    <link rel="apple-touch-icon" href="https://static.cdninstagram.com/rsrc.php/v3/yI/r/apple-touch-icon.png">
    <meta property="og:image:url" content="https://instagram.example/static/images/ico/favicon-200.png">
    """
    check(image_candidates(login_wall) == [], f"logos should be skipped: {image_candidates(login_wall)}")

    poster = '<meta property="og:video:poster" content="https://video.example/frame.jpg">'
    check(image_candidates(poster) == ["https://video.example/frame.jpg"], "video poster")

    check(
        instagram_embed_url("https://www.instagram.com/reel/AbC123/?igsh=xyz")
        == "https://www.instagram.com/reel/AbC123/embed/",
        "reel embed",
    )
    check(
        instagram_embed_url("https://www.instagram.com/reels/AbC123/")
        == "https://www.instagram.com/reel/AbC123/embed/",
        "reels -> reel",
    )
    check(
        instagram_embed_url("https://www.instagram.com/p/PostCode/")
        == "https://www.instagram.com/p/PostCode/embed/",
        "p embed",
    )
    check(instagram_embed_url("https://example.com/p/PostCode/") is None, "non-instagram")
    check(instagram_embed_url("https://www.instagram.com/explore/") is None, "no shortcode")

    check(is_tiktok_url("https://vm.tiktok.com/ZMabcd/"), "vm short link")
    check(is_tiktok_url("https://www.tiktok.com/@user/video/123"), "full video")
    check(not is_tiktok_url("https://www.instagram.com/p/x/"), "not tiktok")
    embed = oembed_url("https://www.tiktok.com/@scout2015/video/6718335390845095173")
    check(embed.startswith("https://www.tiktok.com/oembed?"), f"oembed host {embed}")
    check("url=" in embed and "tiktok.com" in embed, f"oembed query {embed}")

    cover_html = '{"originCover":"https://p16-sign.tiktokcdn-us.com/tos-cover~tplv-origin.image?x=1"}'
    covers = image_candidates(cover_html)
    check(covers == ["https://p16-sign.tiktokcdn-us.com/tos-cover~tplv-origin.image?x=1"], f"cover json {covers}")
    check(
        image_candidates('{"cover":"https://lf16-tiktok-web.tiktokcdn-us.com/obj/tiktok-web-tx/logo.png"}') == [],
        "skip tiktok static",
    )

    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
