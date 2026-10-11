export const VOICE_VIEW_COMMANDS=Object.freeze({
 'voice-viewfl-on':'fl','voice-viewga-on':'ga','voice-viewal-on':'al',
 'voice-viewva-on':'va','voice-viewnc-on':'nc','voice-viewtn-on':'tn',
 'voice-viewsoutheast-on':'southeast','voice-viewlowersoutheast-on':'lower-southeast'
});
export const VOICE_DISPLAY_COMMANDS=Object.freeze([
 ...Object.keys(VOICE_VIEW_COMMANDS),
 ...['fm','awos','ctaf','radar','traffic','lightning','airmet','sigmet','fronts','observation','winds','3k','10k','slideshow1','slideshow2','slideshow3','phasers','torpedoes','generalquarters','schwartz','whitewomen','oneliners','landplane','snakes'].flatMap(key=>['on','off'].map(value=>'voice-'+key+'-'+value))
]);
const aliases=new Map([
 ['lancaster','lkr'],['lkr','lkr'],['l k r','lkr'],
 ['south carolina','sc'],['carolina','sc'],['sc','sc'],['s c','sc'],
 ['crystal river','cgc'],['cgc','cgc'],['c g c','cgc'],
 ['all','all'],
 ['south east','southeast'],['southeast','southeast'],
 ['airport','airport'],['airport camera','airport'],
 ['slideshow','slideshow'],['slide show','slideshow'],
 ['front door','frontdoor'],['frontdoor','frontdoor'],
 ['front porch','frontporch'],['frontporch','frontporch'],['f porch','frontporch'],['porch','frontporch'],
 ['back yard','backyard'],['backyard','backyard'],
 ['back door','backdoor'],['backdoor','backdoor'],
 ['right yard','rightyard'],['rightyard','rightyard'],['r yard','rightyard'],
 ['driveway','driveway'],['driveway side','driveway'],
 ['columbia','columbia'],['columbia airport','columbia'],
 ['atlanta','atlanta'],['atlanta airport','atlanta'],
 ['enable tone','toneon'],['enable motion tone','toneon'],['tone on','toneon'],['toneon','toneon'],['motion tone on','toneon'],
 ['disable tone','toneoff'],['disable motion tone','toneoff'],['tone off','toneoff'],['toneoff','toneoff'],['motion tone off','toneoff']
]);

export const MAP_COMMANDS=Object.freeze(['lkr','sc','cgc','all','southeast']);
export const HOME_COMMANDS=Object.freeze(['airport','slideshow','frontdoor','frontporch','backyard','backdoor','rightyard','driveway','columbia','atlanta','toneon','toneoff']);
export const DISPLAY_COMMANDS=Object.freeze([...MAP_COMMANDS,...HOME_COMMANDS,...VOICE_DISPLAY_COMMANDS]);

export function normalizeMapCommand(value){
 const phrase=String(value??'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim().replace(/^show\s+/,'');
 const voice=phrase.replace(/ /g,'-');if(VOICE_DISPLAY_COMMANDS.includes(voice))return voice;
 return aliases.get(phrase)||null;
}

export function createMapCommandStore({revision=globalThis.crypto.randomUUID()}={}){
 let sequence=0,current=null;
 return {
  issue(value,now=Date.now()){
   const command=normalizeMapCommand(value);if(!command)throw Error('Unknown display command');
   current={command,sequence:++sequence,issuedAt:new Date(now).toISOString(),revision};return current;
  },
  after(value){const after=Number(value)||0;return current&&current.sequence>after?current:{command:null,sequence,revision};}
 };
}
