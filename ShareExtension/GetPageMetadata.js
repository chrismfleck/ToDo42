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
        var image = content('meta[property="og:image"]')
            || content('meta[property="og:image:secure_url"]')
            || content('meta[property="og:image:url"]')
            || content('meta[property="og:video:poster"]')
            || content('meta[name="twitter:image"]')
            || content('meta[name="twitter:image:src"]')
            || content('meta[itemprop="image"]');
        if (!image) {
            var link = document.querySelector('link[rel="image_src"]');
            if (link) { image = link.getAttribute("href") || ""; }
        }
        if (!image) {
            var img = document.querySelector('article img, main img, img[src*="cdninstagram"], img[src*="fbcdn"], img[srcset]');
            if (img) { image = img.currentSrc || img.src || ""; }
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
