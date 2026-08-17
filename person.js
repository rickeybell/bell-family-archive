
document.addEventListener("DOMContentLoaded",()=>{
 const detail=document.getElementById("photo-detail"), close=document.getElementById("detail-close");
 document.querySelectorAll(".photo-card img").forEach(img=>img.addEventListener("click",()=>{
   const c=img.closest(".photo-card");
   document.getElementById("detail-image").src=img.src;
   document.getElementById("detail-date").textContent=c.dataset.date||"";
   document.getElementById("detail-description").textContent=c.dataset.description||"";
   document.getElementById("detail-file").textContent=c.dataset.file||"";
   document.getElementById("detail-people").textContent=(c.dataset.people||"").split("|").filter(Boolean).join(", ")||"Not identified";
   document.getElementById("detail-categories").textContent=(c.dataset.categories||"").split("|").filter(Boolean).join(", ");
   const tags=document.getElementById("detail-tags");tags.innerHTML="";
   (c.dataset.tags||"").split("|").filter(Boolean).forEach(t=>{const s=document.createElement("span");s.className="tag-chip";s.textContent=t;tags.appendChild(s);});
   detail.classList.add("open");detail.setAttribute("aria-hidden","false");
 }));
 const hide=()=>{detail.classList.remove("open");detail.setAttribute("aria-hidden","true");};
 close?.addEventListener("click",hide);document.addEventListener("keydown",e=>{if(e.key==="Escape")hide();});
});
