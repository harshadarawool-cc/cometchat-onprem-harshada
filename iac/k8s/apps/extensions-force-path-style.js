// extensions-force-path-style.js — node `-r` PRELOAD for the extensions service.
//
// WHY: SeaweedFS 4.37 validates every SigV4 signature against the request Host, which MUST equal the
// filer's S3_EXTERNAL_URL (media-onprem.<domain>). The extensions image builds its aws-sdk S3 client
// WITHOUT s3ForcePathStyle, so the SDK defaults to VIRTUAL-HOST addressing (uploads.media-onprem…) →
// the signed Host no longer matches → `SignatureDoesNotMatch` / AccessDenied on whiteboard/document/
// thumbnail uploads. PROVEN in-cluster: virtual-host = FAIL, path-style = OK.
//
// This preload flips the GLOBAL aws-sdk default to path-style (Host stays media-onprem) BEFORE the app
// constructs any S3 client — a config-only fix (no image change, no filer restart). Loaded via the
// container command: node -r /patch/extensions-force-path-style.js -r ./loader.js ./cluster.js
(function () {
  var candidates = ["/app/node_modules/aws-sdk", "aws-sdk", "/node_modules/aws-sdk"];
  for (var i = 0; i < candidates.length; i++) {
    try {
      var AWS = require(candidates[i]);
      AWS.config.update({ s3ForcePathStyle: true });
      console.log("[force-path-style] s3ForcePathStyle=true applied (" + candidates[i] + ")");
      return;
    } catch (e) { /* try next */ }
  }
  console.error("[force-path-style] aws-sdk not resolvable — path-style NOT forced (extensions S3 will 403 on 4.37)");
})();
