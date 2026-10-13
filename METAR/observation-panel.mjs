// The selected station can change without opening observations in broad views.
export function createObservationPanel({panel,getSelected,selectDefault}){
 let view='reset',hiddenByUser=false,explicit=false;
 const preset=()=>['fit-lkr','reset','fit-cgc'].includes(view);
 const sync=()=>{panel.hidden=(!preset()&&!explicit)||hiddenByUser||!getSelected();};
 return {
  setView(value){if(value!==null){view=value;explicit=false;hiddenByUser=false;}sync();},
  selected(){hiddenByUser=false;sync();},
  setVisible(value){explicit=value;hiddenByUser=!value;if(value&&!getSelected())selectDefault(view==='fit-cgc'?'KCGC':'KLKR');sync();},
  snapshot(){return {available:true,visible:!panel.hidden};},
 };
}
