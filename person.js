
document.addEventListener("DOMContentLoaded",()=>{
 // Keep current ages accurate on living relatives' profile pages.
 const today=new Date();
 document.querySelectorAll(".person-page-vitals[data-birthdate]").forEach(vitals=>{
   if(vitals.querySelector(".current-age"))return;
   const [year,month,day]=vitals.dataset.birthdate.split("-").map(Number);
   let age=today.getFullYear()-year;
   const monthNow=today.getMonth()+1;
   if(monthNow<month || (monthNow===month && today.getDate()<day))age--;
   const line=document.createElement("span");
   line.className="current-age";
   line.innerHTML=`<strong>Current age:</strong> ${age}`;
   vitals.appendChild(line);
 });

 // Biography pages no longer have the legacy archive sidebar. Expand the remaining
 // content across the full site width instead of leaving it in the old 270px grid column.
 const shell=document.querySelector(".site-shell");
 if(shell && !shell.querySelector(".archive-sidebar")){
   shell.style.gridTemplateColumns="minmax(0,1fr)";
   const main=shell.querySelector(".archive-content");
   if(main){main.style.width="100%";main.style.maxWidth="1500px";main.style.margin="0 auto";}
 }


 // Keep the biography-page archive count synchronized with the same
 // photo_metadata.json used to generate the person's photo archive.
 const personCount=document.querySelector(".person-count");
 const personName=document.querySelector(".person-hero h1")?.textContent?.trim();
 if(personCount && personName){
   const archivePerson=personCount.dataset.archivePerson||personName;
   fetch("photo_metadata.json",{cache:"no-store"})
     .then(r=>{if(!r.ok)throw new Error("photo metadata unavailable");return r.json();})
     .then(items=>{
       const count=items.filter(x=>Array.isArray(x.people)&&x.people.includes(archivePerson)).length;
       personCount.textContent=`${count} currently identified archive item${count===1?"":"s"}`;
     })
     .catch(err=>console.warn("Biography archive count could not be refreshed:",err));
 }

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
 const hide=()=>{detail?.classList.remove("open");detail?.setAttribute("aria-hidden","true");};
 close?.addEventListener("click",hide);document.addEventListener("keydown",e=>{if(e.key==="Escape")hide();});
});
