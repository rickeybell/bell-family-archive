
document.addEventListener("DOMContentLoaded",()=>{
  // Keep current ages accurate for living relatives as birthdays pass.
  const today=new Date();
  document.querySelectorAll(".tree-person[data-birthdate], .archive-community-card[data-birthdate]").forEach(card=>{
    const vitals=card.querySelector(".tree-vitals");
    if(!vitals || vitals.querySelector(".current-age"))return;
    const [year,month,day]=card.dataset.birthdate.split("-").map(Number);
    let age=today.getFullYear()-year;
    const monthNow=today.getMonth()+1;
    if(monthNow<month || (monthNow===month && today.getDate()<day))age--;
    const line=document.createElement("span");
    line.className="current-age";
    line.innerHTML=`<strong>Current age:</strong> ${age}`;
    vitals.appendChild(line);
  });
  document.querySelectorAll(".tree-person[data-birth-year], .archive-community-card[data-birth-year]").forEach(card=>{
    const vitals=card.querySelector(".tree-vitals");
    if(!vitals || vitals.querySelector(".current-age"))return;
    const age=today.getFullYear()-Number(card.dataset.birthYear);
    const line=document.createElement("span");
    line.className="current-age";
    line.innerHTML=`<strong>Current age:</strong> about ${age}`;
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


  // Keep archive-item counts synchronized with the current generated metadata.
  // Counts therefore reflect the currently identified Website-tagged archive,
  // rather than old hard-coded values.
  const countTargets=[...document.querySelectorAll("[data-archive-person], [data-archive-tag]")];
  if(countTargets.length){
    fetch("photo_metadata.json",{cache:"no-store"})
      .then(r=>{if(!r.ok)throw new Error("metadata unavailable");return r.json();})
      .then(items=>{
        countTargets.forEach(el=>{
          const person=el.dataset.archivePerson;
          const tag=el.dataset.archiveTag;
          const count=person
            ? items.filter(x=>Array.isArray(x.people)&&x.people.includes(person)).length
            : items.filter(x=>Array.isArray(x.tags)&&x.tags.includes(tag)).length;
          if(el.closest("#fallen-first-responders")){
            el.hidden=count===0;
            if(count===0)return;
          }
          const prefix=el.dataset.archivePrefix||"";
          el.textContent=`${prefix}${count} archive item${count===1?"":"s"}`;
        });
      })
      .catch(err=>console.warn("Archive counts could not be refreshed:",err));
  }
  const cards=[...document.querySelectorAll(".photo-card")];

  // Restored display copies can live in organized subfolders while the archive card keeps its identity.
  const restoredPhotoCorrections={
    "1960s_0002(1).jpg":{
      src:"images/1960/1960s_0002_a_Restored.png",
      file:"1960s_0002_a_Restored.png",
      date:"August 1960",
      description:"August 1960 &mdash; Dickey on the far right; Spooky in the center rear. Restored display copy; faces were not generatively altered."
    }
  };
  cards.forEach(card=>{
    const fix=restoredPhotoCorrections[card.dataset.file];
    if(!fix)return;
    const oldFile=card.dataset.file;
    const image=card.querySelector("img");
    if(image){
      image.src=fix.src;
      image.alt=fix.description;
    }
    card.dataset.file=fix.file;
    card.dataset.date=fix.date;
    card.dataset.description=fix.description;
    if(card.dataset.tags){
      const tags=card.dataset.tags.split("|");
      if(!tags.includes("1960"))tags.push("1960");
      card.dataset.tags=tags.join("|");
    }
    const dateStrong=card.querySelector(".photo-date strong");
    if(dateStrong)dateStrong.textContent=fix.date;
    const ident=card.querySelector(".photo-identification");
    if(ident)ident.textContent=fix.description;
    const filename=card.querySelector(".photo-filename");
    if(filename)filename.textContent=fix.file;
    cards.forEach(other=>{
      if(other.dataset.related){
        other.dataset.related=other.dataset.related.split("|").map(f=>f===oldFile?fix.file:f).join("|");
      }
    });
  });

  // Known family-date corrections applied consistently across archive pages.
  const knownDateCorrections={
    "1980s_0031_a.jpg":{
      date:"December 25, 1984",
      tagFrom:"1980",
      tagTo:"1984"
    }
  };
  cards.forEach(card=>{
    const fix=knownDateCorrections[card.dataset.file];
    if(!fix)return;
    card.dataset.date=fix.date;
    const dateStrong=card.querySelector(".photo-date strong");
    if(dateStrong)dateStrong.textContent=fix.date;
    if(card.dataset.tags){
      card.dataset.tags=card.dataset.tags.split("|").map(t=>t===fix.tagFrom?fix.tagTo:t).join("|");
    }
  });

  const detail=document.getElementById("photo-detail");
  const detailClose=document.getElementById("detail-close");
  const imgEl=document.getElementById("detail-image");
  const dateEl=document.getElementById("detail-date");
  const descEl=document.getElementById("detail-description");
  const peopleEl=document.getElementById("detail-people");
  const catEl=document.getElementById("detail-categories");
  const fileEl=document.getElementById("detail-file");
  const tagsEl=document.getElementById("detail-tags");
  const relEl=document.getElementById("detail-related");
  const filterBar=document.getElementById("active-filter");
  const filterLabel=document.getElementById("active-filter-label");
  const clearFilter=document.getElementById("clear-filter");

  const findCard=file=>cards.find(c=>c.dataset.file===file);

  function chip(text,type){
    const b=document.createElement("button");
    b.className="tag-chip"; b.textContent=text;
    b.addEventListener("click",()=>applyFilter(type,text));
    return b;
  }

  function openDetail(card){
    if(!card||!detail)return;
    const image=card.querySelector("img");
    imgEl.src=image?.src||"";
    imgEl.alt=image?.alt||"";
    dateEl.textContent=card.dataset.date||"";
    descEl.textContent=card.dataset.description||"";
    const people=(card.dataset.people||"").split("|").filter(Boolean);
    const cats=(card.dataset.categories||"").split("|").filter(Boolean);
    peopleEl.innerHTML="";
    if(people.length){people.forEach((p,i)=>{peopleEl.appendChild(chip(p,"person")); if(i<people.length-1)peopleEl.append(" ");});}
    else peopleEl.textContent="Not identified";
    catEl.innerHTML="";
    cats.forEach((c,i)=>{catEl.appendChild(chip(c,"category")); if(i<cats.length-1)catEl.append(" ");});
    fileEl.textContent=card.dataset.file||"";
    tagsEl.innerHTML="";
    (card.dataset.tags||"").split("|").filter(Boolean).forEach(t=>tagsEl.appendChild(chip(t,"tag")));
    relEl.innerHTML="";
    (card.dataset.related||"").split("|").filter(Boolean).forEach(file=>{
      const rel=findCard(file); if(!rel)return;
      const item=document.createElement("div"); item.className="related-item";
      const rimg=rel.querySelector("img");
      item.innerHTML=`<img src="${rimg?.src||""}" alt=""><div>${rel.dataset.date||""}</div>`;
      item.addEventListener("click",()=>openDetail(rel));
      relEl.appendChild(item);
    });
    detail.classList.add("open");
    detail.setAttribute("aria-hidden","false");
  }
  function closeDetail(){detail?.classList.remove("open");detail?.setAttribute("aria-hidden","true");}

  cards.forEach(card=>card.querySelector("img")?.addEventListener("click",()=>openDetail(card)));
  detailClose?.addEventListener("click",closeDetail);
  document.addEventListener("keydown",e=>{if(e.key==="Escape")closeDetail();});

  function applyFilter(type,value){
    cards.forEach(card=>{
      let vals=[];
      if(type==="person") vals=(card.dataset.people||"").split("|");
      else if(type==="category") vals=(card.dataset.categories||"").split("|");
      else vals=(card.dataset.tags||"").split("|");
      card.classList.toggle("filtered-out",!vals.includes(value));
    });
    document.querySelectorAll(".year-section").forEach(sec=>{
      const visible=[...sec.querySelectorAll(".photo-card")].some(c=>!c.classList.contains("filtered-out"));
      sec.style.display=visible?"":"none";
    });
    if(filterBar){filterBar.hidden=false;filterLabel.textContent=`Showing ${type}: ${value}`;}
    closeDetail();
    document.getElementById("archive")?.scrollIntoView({behavior:"smooth"});
  }
  function clear(){
    cards.forEach(c=>c.classList.remove("filtered-out"));
    document.querySelectorAll(".year-section").forEach(s=>s.style.display="");
    if(filterBar)filterBar.hidden=true;
  }
  document.querySelectorAll(".filter-link").forEach(btn=>btn.addEventListener("click",()=>applyFilter(btn.dataset.filterType,btn.dataset.filterValue)));
  clearFilter?.addEventListener("click",clear);

  // Portrait still opens in the simple lightbox.
  const box=document.getElementById("lightbox"), boxImg=box?.querySelector("img"), close=document.getElementById("close");
  document.querySelectorAll(".portrait-wrap img, #fallen-first-responders .archive-community-photo img").forEach(img=>img.addEventListener("click",()=>{if(box&&boxImg){boxImg.src=img.src;boxImg.alt=img.alt||"";box.classList.add("open");box.setAttribute("aria-hidden","false");}}));
  const closeBox=()=>{box?.classList.remove("open");box?.setAttribute("aria-hidden","true");};
  close?.addEventListener("click",closeBox);
  box?.addEventListener("click",e=>{if(e.target===box)closeBox();});
});
