(() => {
  "use strict";

  const NS = "http://www.w3.org/2000/svg";

  function cardByHref(href) {
    return document.querySelector(`.family-tree .tree-person[href="${href}"]`);
  }

  function cardByName(name) {
    return [...document.querySelectorAll(".family-tree .tree-person")]
      .find(el => el.querySelector(".tree-name")?.textContent.trim() === name);
  }

  function point(rect, treeRect, where) {
    if (where === "top") {
      return {x:(rect.left+rect.right)/2-treeRect.left, y:rect.top-treeRect.top};
    }
    return {x:(rect.left+rect.right)/2-treeRect.left, y:rect.bottom-treeRect.top};
  }

  function addPath(svg, d) {
    const p = document.createElementNS(NS, "path");
    p.setAttribute("d", d);
    svg.appendChild(p);
  }

  function drawParentsToChildren(svg, treeRect, p1El, p2El, childEls) {
    if (!p1El || !p2El || !childEls.length || !childEls.every(Boolean)) return;

    const p1 = point(p1El.getBoundingClientRect(), treeRect, "bottom");
    const p2 = point(p2El.getBoundingClientRect(), treeRect, "bottom");
    const kids = childEls.map(el => point(el.getBoundingClientRect(), treeRect, "top"));

    const parentBottom = Math.max(p1.y, p2.y);
    const childTop = Math.min(...kids.map(k => k.y));
    const gap = Math.max(16, childTop - parentBottom);
    const barY = parentBottom + Math.min(42, Math.max(22, gap * 0.42));

    const allX = [p1.x, p2.x, ...kids.map(k => k.x)];
    const left = Math.min(...allX);
    const right = Math.max(...allX);

    addPath(svg, `M ${p1.x} ${p1.y} V ${barY}`);
    addPath(svg, `M ${p2.x} ${p2.y} V ${barY}`);
    addPath(svg, `M ${left} ${barY} H ${right}`);

    for (const kid of kids) {
      addPath(svg, `M ${kid.x} ${barY} V ${kid.y}`);
    }
  }

  function drawParentToChild(svg, treeRect, parentEl, childEl) {
    if (!parentEl || !childEl) return;
    const p = point(parentEl.getBoundingClientRect(), treeRect, "bottom");
    const c = point(childEl.getBoundingClientRect(), treeRect, "top");
    addPath(svg, `M ${p.x} ${p.y} V ${c.y}`);
  }

  function redraw() {
    const tree = document.querySelector(".family-tree");
    if (!tree) return;

    let svg = document.getElementById("familyTreeLineLayer");
    if (!svg) {
      svg = document.createElementNS(NS, "svg");
      svg.id = "familyTreeLineLayer";
      tree.prepend(svg);
    }
    svg.replaceChildren();

    const r = tree.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${r.width} ${r.height}`);
    svg.setAttribute("preserveAspectRatio", "none");

    const buster = cardByHref("buster.html");
    const alma = cardByHref("alma.html");
    const spooky = cardByHref("spooky.html");
    const helen = cardByName("Helen Bell");
    const dickey = cardByHref("dickey.html");
    const heather = cardByHref("heather.html");
    const debbie = cardByHref("debbie.html");
    const rickey = cardByHref("rickey.html");
    const stephanie = cardByHref("stephanie.html");
    const samatha = cardByHref("samatha.html");
    const jarred = cardByHref("jarred.html");
    const dominique = cardByHref("dominique.html");
    const sophia = cardByHref("sophia.html");
    const olivia = cardByHref("olivia.html");
    const ivy = cardByHref("ivy.html");

    drawParentsToChildren(svg, r, buster, alma, [spooky, dickey]);
    drawParentsToChildren(svg, r, spooky, helen, [heather]);
    drawParentsToChildren(svg, r, dickey, debbie, [rickey]);
    drawParentsToChildren(svg, r, rickey, stephanie, [samatha, jarred]);
    drawParentToChild(svg, r, samatha, sophia);
    drawParentsToChildren(svg, r, jarred, dominique, [olivia, ivy]);
  }

  let timer;
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(() => requestAnimationFrame(redraw), 80);
  }

  document.addEventListener("DOMContentLoaded", schedule);
  window.addEventListener("load", schedule);
  window.addEventListener("resize", schedule);

  document.querySelectorAll(".family-tree img").forEach(img => {
    if (!img.complete) img.addEventListener("load", schedule, {once:true});
  });

  if ("ResizeObserver" in window) {
    const tree = document.querySelector(".family-tree");
    if (tree) new ResizeObserver(schedule).observe(tree);
  }
})();
