
document.addEventListener("DOMContentLoaded",()=>{
  const cards=[...document.querySelectorAll(".photo-card")];
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
  document.querySelectorAll(".portrait-wrap img").forEach(img=>img.addEventListener("click",()=>{if(box&&boxImg){boxImg.src=img.src;box.classList.add("open");}}));
  close?.addEventListener("click",()=>box?.classList.remove("open"));
  box?.addEventListener("click",e=>{if(e.target===box)box.classList.remove("open");});
});
