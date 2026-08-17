
document.addEventListener("DOMContentLoaded",()=>{
 const cards=[...document.querySelectorAll(".photo-card")];

 // Use the restored display copy from the organized 1960 image folder.
 cards.forEach(card=>{
   if(card.dataset.file!=="1960s_0002(1).jpg")return;
   const image=card.querySelector("img");
   const description="August 1960 — Dickey on the far right; Spooky in the center rear. Restored display copy; faces were not generatively altered.";
   if(image){image.src="images/1960/1960s_0002_a_Restored.png";image.alt=description;}
   card.dataset.file="1960s_0002_a_Restored.png";
   card.dataset.date="August 1960";
   card.dataset.description=description;
   if(card.dataset.tags){
     const tags=card.dataset.tags.split("|");
     if(!tags.includes("1960"))tags.push("1960");
     card.dataset.tags=tags.join("|");
   }
   const dateStrong=card.querySelector(".photo-date strong");if(dateStrong)dateStrong.textContent="August 1960";
   const ident=card.querySelector(".photo-identification");if(ident)ident.textContent=description;
   const filename=card.querySelector(".photo-filename");if(filename)filename.textContent="1960s_0002_a_Restored.png";
 });

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
