(function () {
  const zones = Array.from(document.querySelectorAll(".zone"));
  const pulse = document.getElementById("pulse");
  if (!zones.length) return;

  let i = 0;
  let timer;

  function hit(zone) {
    zones.forEach((z) => z.classList.remove("hit"));
    zone.classList.add("hit");
    if (pulse) {
      pulse.classList.remove("on");
      // reflow so animation restarts
      void pulse.offsetWidth;
      pulse.classList.add("on");
    }
  }

  function cycle() {
    hit(zones[i % zones.length]);
    i += 1;
  }

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  cycle();
  if (!reduced) timer = setInterval(cycle, 1600);

  zones.forEach((zone, idx) => {
    zone.addEventListener("mouseenter", () => {
      clearInterval(timer);
      hit(zone);
      i = idx + 1;
    });
    zone.addEventListener("mouseleave", () => {
      clearInterval(timer);
      if (!reduced) timer = setInterval(cycle, 1600);
    });
  });

  // Prefer latest release tag in the download button when API is reachable
  const meta = document.getElementById("download-meta");
  const btn = document.getElementById("download-btn");
  if (!meta || !btn) return;

  fetch("https://api.github.com/repos/SuzalShrestha/touchmac/releases/latest")
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.tag_name) return;
      const asset = (data.assets || []).find((a) => /\.zip$/i.test(a.name || ""));
      meta.textContent = asset ? `${data.tag_name} · .zip` : `${data.tag_name}`;
      if (asset && asset.browser_download_url) {
        btn.href = asset.browser_download_url;
      }
    })
    .catch(() => {});
})();
