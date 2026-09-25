var GetPageMetadata = function() {};

GetPageMetadata.prototype = {
    run: function(arguments) {
        function content(selector) {
            var el = document.querySelector(selector);
            return el ? (el.getAttribute("content") || "") : "";
        }
        function abs(url) {
            if (!url) { return ""; }
            try { return new URL(url, document.baseURI).href; } catch (e) { return url; }
        }
        function looksLikeLogo(url) {
            var lower = (url || "").toLowerCase();
            if (!lower) { return true; }
            if (lower.indexOf("favicon") !== -1) { return true; }
            if (lower.indexOf("apple-touch-icon") !== -1) { return true; }
            if (lower.indexOf("abs.twimg.com") !== -1) { return true; }
            if (lower.indexOf("/rweb/") !== -1 && lower.indexOf("/og/image") !== -1) { return true; }
            return false;
        }
        function preferredTwitterMedia(url) {
            if (!url || !isTwitterImageCDN(url)) { return url; }
            try {
                var parsed = new URL(url, document.baseURI);
                parsed.searchParams.delete("format");
                parsed.searchParams.delete("name");
                parsed.searchParams.set("format", "jpg");
                parsed.searchParams.set("name", "large");
                // media_url_https sometimes ends in .jpg — strip for format query.
                parsed.pathname = parsed.pathname.replace(/\.(jpe?g|png|webp)$/i, "");
                return parsed.href;
            } catch (e) {
                return url;
            }
        }
        function isTwitterImageCDN(url) {
            var lower = (url || "").toLowerCase();
            if (lower.indexOf("pbs.twimg.com/") === -1) { return false; }
            return lower.indexOf("/media/") !== -1
                || lower.indexOf("/card_img/") !== -1
                || lower.indexOf("/amplify_video_thumb/") !== -1
                || lower.indexOf("/ext_tw_video_thumb/") !== -1
                || lower.indexOf("/tweet_video_thumb/") !== -1;
        }
        function firstTwitterMedia() {
            var html = document.documentElement ? document.documentElement.innerHTML : "";
            var match = html.match(/https?:\/\/pbs\.twimg\.com\/(?:media|card_img)\/[A-Za-z0-9_\/-]+(?:\.(?:jpe?g|png|webp))?(?:\?[^"'\\\s]*)?/i);
            if (match) { return preferredTwitterMedia(match[0]); }
            var img = document.querySelector('img[src*="pbs.twimg.com/media/"], img[src*="pbs.twimg.com/card_img/"]');
            if (img) { return preferredTwitterMedia(img.currentSrc || img.src || ""); }
            return "";
        }
        var image = firstTwitterMedia()
            || content('meta[property="og:image"]')
            || content('meta[property="og:image:secure_url"]')
            || content('meta[property="og:image:url"]')
            || content('meta[property="og:video:poster"]')
            || content('meta[name="twitter:image"]')
            || content('meta[name="twitter:image:src"]')
            || content('meta[itemprop="image"]');
        if (looksLikeLogo(image)) { image = ""; }
        if (image && isTwitterImageCDN(image)) {
            image = preferredTwitterMedia(image);
        }
        if (!image) {
            var link = document.querySelector('link[rel="image_src"]');
            if (link) { image = link.getAttribute("href") || ""; }
            if (looksLikeLogo(image)) { image = ""; }
        }
        if (!image) {
            var img = document.querySelector('article img, main img, img[src*="cdninstagram"], img[src*="fbcdn"], img[src*="tiktokcdn"], img[src*="muscdn"], img[srcset]');
            if (img) { image = img.currentSrc || img.src || ""; }
            if (looksLikeLogo(image)) { image = ""; }
        }
        arguments.completionFunction({
            "URL": document.URL || "",
            "title": content('meta[property="og:title"]') || document.title || "",
            "description": content('meta[property="og:description"]') || content('meta[name="description"]') || "",
            "imageURL": abs(image)
        });
    },

    finalize: function(arguments) {}
};

var ExtensionPreprocessingJS = new GetPageMetadata();
