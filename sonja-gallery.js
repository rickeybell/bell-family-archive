document.addEventListener("DOMContentLoaded", async () => {
  const host = document.querySelector(".embedded-archive-content[data-gallery-source]");
  if (!host) return;

  try {
    const response = await fetch(host.dataset.gallerySource, { cache: "no-store" });
    if (!response.ok) throw new Error(`Gallery request failed with ${response.status}`);

    const source = new DOMParser().parseFromString(await response.text(), "text/html");
    const galleryStyle = source.querySelector("head style");
    const galleryShell = source.querySelector(".archive-shell");
    const galleryViewer = source.querySelector("#viewer");
    const galleryScript = [...source.scripts].find(script => script.textContent.includes("const archiveItems="));
    if (!galleryStyle || !galleryShell || !galleryViewer || !galleryScript) {
      throw new Error("The generated gallery is incomplete");
    }

    const style = document.createElement("style");
    style.dataset.sonjaGallery = "true";
    style.textContent = galleryStyle.textContent;
    document.head.appendChild(style);

    host.replaceChildren(
      document.importNode(galleryShell, true),
      document.importNode(galleryViewer, true)
    );
    host.setAttribute("aria-busy", "false");

    const runner = document.createElement("script");
    runner.dataset.sonjaGallery = "true";
    runner.textContent = galleryScript.textContent;
    document.body.appendChild(runner);
  } catch (error) {
    console.error("Sonja gallery could not be loaded:", error);
    host.setAttribute("aria-busy", "false");
    host.innerHTML = '<p class="embedded-archive-error">Sonja&rsquo;s gallery could not be loaded. Please refresh the page and try again.</p>';
  }
});
