export const channels=['122.725:live','122.725:buffered','120.825:live','120.825:buffered'];
export function channelKey(frequency,mode){const key=`${frequency}:${mode}`;if(!channels.includes(key))throw Error('Invalid radio channel');return key;}
export function encodeFrame(key,sequence,at,audio){
 const bytes=new Uint8Array(24+audio.length),view=new DataView(bytes.buffer);bytes.set([77,82,65,68,channels.indexOf(key),1,0,0]);view.setUint32(8,sequence);view.setFloat64(12,at);view.setUint32(20,audio.length);bytes.set(audio,24);return bytes;
}
export function decodeFrame(input){
 const bytes=input instanceof Uint8Array?input:new Uint8Array(input),view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
 if(bytes.length<24||bytes[0]!==77||bytes[1]!==82||bytes[2]!==65||bytes[3]!==68||bytes[5]!==1||!channels[bytes[4]]||view.getUint32(20)!==bytes.length-24||bytes.length>65560)throw Error('Invalid radio frame');
 const at=view.getFloat64(12);if(!Number.isFinite(at))throw Error('Invalid timestamp');return {key:channels[bytes[4]],sequence:view.getUint32(8),at,audio:bytes.subarray(24)};
}
