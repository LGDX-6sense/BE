'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {".vercel/project.json": "2d795e372d6360b88e36b333435d6f18",
".vercel/README.txt": "2b13c79d37d6ed82a3255b83b6815034",
"assets/AssetManifest.bin": "a0b930d3aeee29fc2c7fd763d252716a",
"assets/AssetManifest.bin.json": "0c2c85bef8f01c1c7b70b63bb82f0aa3",
"assets/assets/characters/audio.png": "37d8f4a44b6ab92bb5572dd1fc5fe6ee",
"assets/assets/characters/audio_plain.png": "863ad4acb36316a882e0b578a827da6c",
"assets/assets/characters/idle.png": "2fa15b761ece74d503d3e4b2e09fee88",
"assets/assets/characters/idle_plain.png": "4278a914887900eebba689cb2dfab01b",
"assets/assets/characters/photo.png": "758f582435ff118bfa741f552ec04d99",
"assets/assets/characters/photo_plain.png": "9c6d1373a3634195c3faa92e27136aa6",
"assets/assets/characters/rebo_Image.png": "123a228a2950f4d236557691181fc2bf",
"assets/assets/characters/replying.png": "3461d7afbc9d17ccfd1d6300f3476835",
"assets/assets/icon/1.png": "2dbe068633eacdff08359fab38640cbd",
"assets/assets/icon/AI.png": "ab474e2cef2e1f01386e50fa444f292c",
"assets/assets/icon/ai_.png": "34e53bec91f28c2bea230596fe287f81",
"assets/assets/icon/ai_un.png": "2cfa1b499eb4d39056ac8af8ec28af58",
"assets/assets/icon/app_icon.png": "eaf53be6e2bd5f6e02fccbeef9846fbf",
"assets/assets/icon/arrow.png": "404565f43088b70f199b85ff81f197aa",
"assets/assets/icon/bar_care.png": "44191dd7732f08b3fdb4fc123906e5af",
"assets/assets/icon/bar_care_un.png": "6c9df75f356e80e916ee143db4745e7c",
"assets/assets/icon/bar_chat.png": "536e8062a8710b22ce4d4598e26e65bd",
"assets/assets/icon/bar_chat_un.png": "3b4ffe2ee0b1e97e52b3aaf2fb86b06b",
"assets/assets/icon/bar_dev.png": "86347794ebf07b15caef30360855473d",
"assets/assets/icon/bar_dev_un.png": "09746358390d74d5205a9d5511c74e0d",
"assets/assets/icon/bar_home.png": "e5fc956e2be29181656e1b17aad8dafb",
"assets/assets/icon/bar_home_un.png": "c306356d02db5ad0b044a4235b8cbfb3",
"assets/assets/icon/bar_menu.png": "3b522111dbe3ad2cda01edb8995b91cb",
"assets/assets/icon/bar_menu_un.png": "be9ccafe3ef40c0319253fdae5d58e98",
"assets/assets/icon/bell.png": "4addc40cdffe28fb5f33d487d7be54a8",
"assets/assets/icon/care.png": "a38dc987d7ae903c1e951936e8778a64",
"assets/assets/icon/care_un.png": "7e9e83df925d85d952ab69126ca74fa9",
"assets/assets/icon/Chart.png": "8a7802ff78d544b53d300d059fa5b525",
"assets/assets/icon/chat_arhive.png": "9780f28445dcd92c02825109855b0f61",
"assets/assets/icon/chat_close.png": "b83106521b19d63b2f787a5637741472",
"assets/assets/icon/chat_newchat.png": "abe738b95ba09fe8d74a7e57bd1bfe5f",
"assets/assets/icon/Chat_search.png": "731500efc1558c40f27d1cf22e78f309",
"assets/assets/icon/close.png": "370b112ed719d59bf26f817726b4b552",
"assets/assets/icon/device.png": "840c44e66dcfe0767e0b294b19fab12a",
"assets/assets/icon/device_un.png": "bcb09f78a9961575d579e4b9c400576d",
"assets/assets/icon/down.png": "3593904bb18f416fa3a73853b05c1f9b",
"assets/assets/icon/edit.png": "fa422e76f9fe866f64493c94637631a1",
"assets/assets/icon/home.png": "950000f1142ee02101568612b4c114ca",
"assets/assets/icon/home_1.png": "c6c8ccc36058b9149f46d11c32d364d9",
"assets/assets/icon/home_2.png": "b005a14b51120f7f3f1561738929c35a",
"assets/assets/icon/home_air.png": "9650da1b28d3a4b56a0407169d59c93c",
"assets/assets/icon/home_bell.png": "8375c2799338c669ca0457b81a057ffb",
"assets/assets/icon/home_meatballs.png": "4286dbb6036129239ae38df10f5b350e",
"assets/assets/icon/home_plus.png": "596ba762e9e61a06629a1a77c7878e7c",
"assets/assets/icon/home_refrigerator.png": "93f171381f3d1aa028c3eff86ea5b843",
"assets/assets/icon/home_thinq.png": "d5d49950cdc0bfa6fd4144bb55be7ba9",
"assets/assets/icon/home_un.png": "04e21ddac3f10c6d8ff069ff501eefaa",
"assets/assets/icon/home_washing.png": "8ea17f521aaf63a8f296f574c3a42e80",
"assets/assets/icon/k.png": "38c6760259d808dd53c8aa6cfe725eeb",
"assets/assets/icon/Line_up.png": "f10151c4c7bb32c5bcfa4c4653ba62c9",
"assets/assets/icon/main_img1.png": "33e4c72cf9c0dbbbd3ccf5fcb69bc315",
"assets/assets/icon/main_img2.png": "93bd1c0f6fe149c1404a335db9e734b2",
"assets/assets/icon/Meatball.png": "84a369685873031b813e88160ea21251",
"assets/assets/icon/meatbell.png": "84a369685873031b813e88160ea21251",
"assets/assets/icon/menu.png": "fa89c5f437c3aa56b41513d12b12803d",
"assets/assets/icon/menu_un.png": "3be0fe99dfc5e3cf1cc9c7df2c6354b0",
"assets/assets/icon/mic.png": "66d7e66e31cec4cf209d63ccb2490c80",
"assets/assets/icon/mic_non.png": "46f17824c4dce760f45dfa697bd6116d",
"assets/assets/icon/Right.png": "ad631e0ad5e32e1c22a20932476b72af",
"assets/assets/icon/send.png": "4c91cb5e9ee23e26a4698ad3f1fdf894",
"assets/assets/icon/send_non.png": "525c9b1697c905adf8e92f08c54eb546",
"assets/assets/icon/stop.png": "ff9c4dec9519a64a4f5bc5150843a8f9",
"assets/assets/icon/time.png": "a9e24bc598e3ae21910fb94cb51b1abf",
"assets/assets/icon/Widget_add.png": "317037515a1adb946a560f93da597b7b",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "286539bc31014c1e08b840970d23dba4",
"assets/NOTICES": "a33fec471fbc8512e5bab546dcf2ef03",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"flutter_bootstrap.js": "e7b2763fb59122add02ff4237af746ad",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "f437a76615f27d140918af65642b8fcb",
"/": "f437a76615f27d140918af65642b8fcb",
"main.dart.js": "46fb1e6524ba7995b0612e41900c5632",
"manifest.json": "ebef851799c527da5675f91fec2ebfee",
"version.json": "a7e55a991cc69f60ca0a7cbd4169ae40"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
