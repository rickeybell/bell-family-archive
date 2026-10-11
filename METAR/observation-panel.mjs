// The selected station can change without opening observations in broad views.
export function createObservationPanel({panel,getSelected,selectDefault}){
 let view='reset',hiddenByUser=false;
 const available=()=>['fit-lkr','reset','fit-cgc'].includes(view);
 const sync=()=>{panel.hidden=!available()||hiddenByUser||!getSelected();};
 return {
  setView(value){view=value;hiddenByUser=false;sync();},
  selected(){hiddenByUser=false;sync();},
  setVisible(value){if(value&&!available())throw Error('Choose Lancaster, SC or Crystal River to open Latest Observation');hiddenByUser=!value;if(value&&!getSelected())selectDefault(view==='fit-cgc'?'KCGC':'KLKR');sync();},
  snapshot(){return {available:available(),visible:!panel.hidden};},
 };
}
