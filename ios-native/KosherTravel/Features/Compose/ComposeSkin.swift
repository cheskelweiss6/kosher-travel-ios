import Foundation

/// The live composer's look inside the native app only (Cheskel, Oct 23 2026: "Let's make this more attractive and
/// more modern"). The posting flow itself (every step, field, check and upload) stays the live app's own code; this
/// script only restyles it when the screen is "compose" in the native shell (html.kt-shell), so the website and the
/// store app are untouched:
/// - a segmented progress bar instead of "Step 1 of 4", a back arrow, large serif step titles, a slide between steps;
/// - the Next button as a large navy button pinned to the bottom, above the keyboard, with a light haptic;
/// - the media step as a big soft drop area; picked media as a big first preview with numbered thumbnails below;
/// - soft search and text fields, the community-rules note as a quiet info row (its words unchanged);
/// - every remove (photo, video, place, stop) and leaving step 1 with something picked asks first, in a sheet with a
///   red Remove / Discard and Cancel (Cheskel, Oct 23 2026, 9:20 AM: every delete is red and asks for confirmation);
/// - the web's own Share chooser (entry points that don't pass a kind) as two large cards.
/// After a native start with a kind (as=quick|guide), the web chooser never shows: backing out of step 1 closes the
/// screen to the native chooser. Sending or posted sets the cookie kt_cmp_done, which ComposeFlow reads to close.
enum ComposeSkin {
    static let doneCookie = "kt_cmp_done"

    static let script = #"""
(function(){try{
  var S=window.__KT_SHELL__; if(!S||S.screen!=='compose')return;
  var de=null, st=null;
  var cls=function(){ de=document.documentElement; if(!de)return false; de.classList.add('ktc'); if(S.as)de.classList.add('ktc-as');
    if(!st){ st=document.createElement('style'); st.id='ktc-style'; st.textContent="\nhtml.ktc .ktc-head{background:#fff!important;-webkit-backdrop-filter:none!important;backdrop-filter:none!important;border-bottom:0!important}\nhtml.ktc .ktc-head>div:first-child{height:52px!important;padding:0 6px!important}\nhtml.ktc .ktc-stepno{display:none!important}\nhtml.ktc .ktc-title{font-size:17px!important;font-weight:600!important;color:#191e3b!important;letter-spacing:-.2px}\nhtml.ktc .ktc-head>div:first-child{position:relative}\nhtml.ktc .ktc-center{position:absolute!important;left:50%;top:50%;transform:translate(-50%,-50%);max-width:62%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}\nhtml.ktc .ktc-title.ktc-hide{opacity:0;transition:opacity .2s}\nhtml.ktc .ktc-back{width:44px!important;height:44px!important;border-radius:22px!important;color:#191e3b!important;position:relative}\nhtml.ktc .ktc-back>svg{opacity:0}\nhtml.ktc .ktc-back::before{content:\"\";position:absolute;inset:0;margin:auto;width:24px;height:24px;background:#191e3b;-webkit-mask:url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'><path d='M15 18l-6-6 6-6'/></svg>\") center/contain no-repeat;mask:url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'><path d='M15 18l-6-6 6-6'/></svg>\") center/contain no-repeat}\nhtml.ktc .ktc-back:active{background:rgba(25,30,59,.06)}\nhtml.ktc .ktc-track{height:4px!important;margin:2px 16px 10px!important;background:#e8e9ef!important;border-radius:2px;overflow:hidden;\n  --seg:calc((100% - (var(--ktc-of,4) - 1) * 4px) / var(--ktc-of,4));\n  -webkit-mask:repeating-linear-gradient(90deg,#000 0 var(--seg),transparent var(--seg) calc(var(--seg) + 4px));\n  mask:repeating-linear-gradient(90deg,#000 0 var(--seg),transparent var(--seg) calc(var(--seg) + 4px))}\nhtml.ktc .ktc-track>div{height:4px!important;background:#191e3b!important;transition:width .35s cubic-bezier(.2,.8,.2,1)!important}\nhtml.ktc .ktc-next{position:fixed!important;z-index:60!important;left:16px!important;right:16px!important;width:auto!important;\n  bottom:calc(max(env(safe-area-inset-bottom,0px),14px) + var(--ktc-kb,0px))!important;height:54px!important;border-radius:27px!important;\n  font-size:17px!important;font-weight:600!important;letter-spacing:-.1px;padding:0 24px!important;\n  box-shadow:0 8px 24px rgba(25,30,59,.22),0 1px 2px rgba(25,30,59,.12);transition:transform .12s ease,background-color .2s ease,opacity .2s ease,bottom .2s ease}\nhtml.ktc .ktc-next:not(:disabled){background:#191e3b!important;color:#fff!important}\nhtml.ktc .ktc-next:disabled{background:#e8e9ef!important;color:#9a9db0!important;box-shadow:none}\nhtml.ktc .ktc-next:not(:disabled):active{transform:scale(.97)}\nhtml.ktc .ktc-headspacer{width:44px;height:44px}\nhtml.ktc .ktc-body{padding-bottom:calc(112px + env(safe-area-inset-bottom,0px))!important}\nhtml.ktc .ktc-body.ktc-big::before{content:attr(data-ktc-title);display:block;font-family:ui-serif,Georgia,\"Times New Roman\",serif;font-size:30px;line-height:1.12;font-weight:700;color:#191e3b;letter-spacing:-.4px;margin:6px 0 14px}\nhtml.ktc .ktc-enter{animation:ktcIn .32s cubic-bezier(.2,.8,.2,1)}\nhtml.ktc .ktc-back-dir.ktc-enter{animation-name:ktcInBack}\n@keyframes ktcIn{from{opacity:0;transform:translateX(18px)}to{opacity:1;transform:none}}\n@keyframes ktcInBack{from{opacity:0;transform:translateX(-18px)}to{opacity:1;transform:none}}\nhtml.ktc .ktc-drop{border:0!important;background:#f3f4f8!important;border-radius:24px!important;min-height:min(62vh,440px)!important;\n  box-shadow:inset 0 0 0 1px rgba(25,30,59,.06);transition:transform .15s ease,background-color .2s}\nhtml.ktc .ktc-drop:active{transform:scale(.985);background:#eceef4!important}\nhtml.ktc .ktc-grid{gap:6px!important;counter-reset:ktcn}\nhtml.ktc .ktc-grid>*{position:relative;counter-increment:ktcn}\nhtml.ktc .ktc-grid .ktc-media{border-radius:14px!important;overflow:hidden}\nhtml.ktc .ktc-grid>.ktc-tile:first-child{grid-column:1/-1!important}\nhtml.ktc .ktc-grid>.ktc-tile:first-child .ktc-media{aspect-ratio:4/5!important;height:auto!important;border-radius:20px!important}\nhtml.ktc .ktc-grid>.ktc-tile:not(:first-child)::after{content:counter(ktcn);position:absolute;top:8px;left:8px;min-width:24px;height:24px;padding:0 7px;border-radius:12px;\n  background:rgba(25,30,59,.82);color:#fff;font:600 13px/24px -apple-system,system-ui,sans-serif;text-align:center;pointer-events:none;z-index:3}\nhtml.ktc .ktc-note{background:transparent!important;border:0!important;border-top:1px solid #eceef3!important;border-radius:0!important;padding:14px 2px 0!important;color:#6b7085!important;font-size:13px!important}\nhtml.ktc .ktc-note svg{width:18px!important;height:18px!important;color:#191e3b!important;opacity:.75}\nhtml.ktc .ktc-body input[type=text],html.ktc .ktc-body input[type=search],html.ktc .ktc-body input:not([type]),html.ktc .ktc-body textarea{\n  background:#f3f4f8!important;border:1px solid transparent!important;border-radius:14px!important;font-size:17px!important;min-height:50px;box-shadow:none!important;transition:border-color .2s,background-color .2s}\nhtml.ktc .ktc-body input[type=text]:focus,html.ktc .ktc-body input[type=search]:focus,html.ktc .ktc-body input:not([type]):focus,html.ktc .ktc-body textarea:focus{\n  background:#fff!important;border-color:#191e3b!important;outline:none!important}\nhtml.ktc .ktc-row{min-height:56px;border-radius:14px!important}\nhtml.ktc .ktc-row:active{background:#f3f4f8!important}\nhtml.ktc.ktc-as [data-testid=share-sheet],html.ktc.ktc-as [data-testid=share-sheet-backdrop]{visibility:hidden!important}\nhtml.ktc .ktc-tip{background:#f6f7fa!important;border:0!important;border-radius:14px!important;color:#5b6075!important}\nhtml.ktc .ktc-body h2.font-serif{font-size:30px!important;line-height:1.12!important;letter-spacing:-.4px}\nhtml.ktc .ktc-body h2.font-serif+p{font-size:15px!important;color:#6b7085!important;margin-top:6px!important}\nhtml.ktc [data-testid=share-sheet]{border-radius:28px 28px 0 0!important}\nhtml.ktc [data-testid=share-sheet]>div.border-t{border:0!important;display:grid;grid-template-columns:1fr 1fr;gap:12px;padding:4px 16px 10px}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row{border:0!important;border-radius:24px!important;background:#f4f5f9!important;min-height:188px!important;padding:18px 16px!important;\n  flex-direction:column!important;align-items:flex-start!important;justify-content:flex-start!important;gap:14px!important;position:relative;transition:transform .12s ease}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row:active{transform:scale(.97)}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row>span:first-child{width:56px!important;height:56px!important;border:0!important;background:#191e3b!important;color:#fff!important}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row>span:first-child svg{width:26px!important;height:26px!important}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row>span:nth-child(2)>span:first-child{flex-direction:column;align-items:flex-start!important;gap:4px!important}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row>span:nth-child(2)>span:first-child>span:first-child,html.ktc [data-testid=share-sheet] [data-testid=share-inspiration]>span:nth-child(2)>span:first-child{font-size:18px!important}\nhtml.ktc [data-testid=share-sheet] .kt-ss-row>svg:last-child{display:none}\n\n.ktc-as-ov{position:fixed;inset:0;z-index:2147483000;background:rgba(10,12,25,.38);display:flex;flex-direction:column;justify-content:flex-end;padding:0 10px calc(max(env(safe-area-inset-bottom,0px),10px));animation:ktcFade .18s ease}\n.ktc-as-card{background:rgba(255,255,255,.97);border-radius:16px;overflow:hidden;margin-bottom:8px;animation:ktcUp .26s cubic-bezier(.2,.8,.2,1)}\n.ktc-as-msg{padding:14px 16px;text-align:center;font:400 13px/1.35 -apple-system,system-ui,sans-serif;color:#6b7085;border-bottom:1px solid #e6e7ec}\n.ktc-as-btn{display:block;width:100%;min-height:57px;border:0;background:transparent;font:400 20px -apple-system,system-ui,sans-serif;color:#191e3b}\n.ktc-as-btn.ktc-red{color:#ED4956}\n.ktc-as-btn.ktc-cancel{font-weight:600;background:#fff;border-radius:16px}\n.ktc-as-btn:active{background:#f0f1f5}\n@keyframes ktcFade{from{opacity:0}to{opacity:1}}\n@keyframes ktcUp{from{transform:translateY(40px);opacity:0}to{transform:none;opacity:1}}\n"; }
    if(!st.isConnected){ (document.head||de).appendChild(st); } return true; };
  if(!cls()){ var iv=setInterval(function(){ if(cls())clearInterval(iv); },10); }
  document.addEventListener('DOMContentLoaded',cls);
  var post=function(m){try{window.webkit.messageHandlers.ktShell.postMessage(m);}catch(e){}};
  var haptic=(function(){var lb=null;return function(){try{ if(!lb){var i=document.createElement('input');i.type='checkbox';i.setAttribute('switch','');i.id='ktc-hap';
      lb=document.createElement('label');lb.htmlFor='ktc-hap';lb.style.cssText='position:fixed;left:-99px;top:-99px;width:1px;height:1px;opacity:0;pointer-events:none';
      i.style.cssText=lb.style.cssText; document.body.appendChild(i); document.body.appendChild(lb);} lb.click(); }catch(e){}};})();
  var lastKey='', lastN=0, entered=false, closed=false;
  var findText=function(root,re,sel){var els=root.querySelectorAll(sel||'div,span,p'); for(var i=0;i<els.length;i++){var t=els[i];
      if(t.childElementCount===0&&re.test((t.textContent||'').trim()))return t;} return null;};
  var scrollParent=function(el){for(var p=el.parentElement;p&&p!==document.body;p=p.parentElement){var o=getComputedStyle(p).overflowY; if(o==='auto'||o==='scroll')return p;} return null;};
  var tag=function(){
    if(de&&!de.classList.contains('ktc'))cls(); if(st&&!st.isConnected)cls();
    // the web's own chooser after a native start (its X from step 1): close back to the native chooser
    if(S.as && entered && !closed && document.querySelector('[data-testid=share-sheet]')){closed=true; post({type:'close'}); return;}
    // sending / posted: the native side closes its chooser too
    if(document.querySelector('[data-testid=post-in-background]')||findText(document.body,/^(Your story is live|Posted!|Saved on your phone)$/,'h2')){
      try{document.cookie='kt_cmp_done='+Date.now()+'; path=/; max-age=900';}catch(e){}
    }
    var stepEl=findText(document.body,/^Step \d+ of \d+$/,'div'); if(!stepEl)return;
    entered=true;
    var m=(stepEl.textContent||'').match(/Step (\d+) of (\d+)/), n=+m[1], of=+m[2];
    var titleEl=stepEl.previousElementSibling, row=stepEl.parentElement&&stepEl.parentElement.parentElement, head=row&&row.parentElement;
    if(!titleEl||!row||!head)return;
    de.style.setProperty('--ktc-of',of);
    stepEl.classList.add('ktc-stepno'); titleEl.classList.add('ktc-title'); if(titleEl.parentElement)titleEl.parentElement.classList.add('ktc-center'); head.classList.add('ktc-head');
    var back=row.firstElementChild; if(back&&back.tagName==='BUTTON')back.classList.add('ktc-back');
    var nx=row.lastElementChild;
    if(nx&&nx.tagName==='BUTTON'){ if(!nx.classList.contains('ktc-next')){nx.classList.add('ktc-next'); nx.addEventListener('click',function(){ if(!nx.disabled)haptic(); });} }
    var track=head.lastElementChild; if(track&&track!==row)track.classList.add('ktc-track');
    var body=head.nextElementSibling; if(!body)return;
    body.classList.add('ktc-body');
    var title=(titleEl.textContent||'').trim(), key=title+'|'+n+'|'+of;
    var hasIntro=!!body.querySelector('h2.font-serif,h1');
    if(!hasIntro){ body.classList.add('ktc-big'); body.setAttribute('data-ktc-title',title); titleEl.classList.add('ktc-hide'); }
    else { body.classList.remove('ktc-big'); titleEl.classList.remove('ktc-hide'); }
    if(key!==lastKey){
      if(lastKey){ body.classList.toggle('ktc-back-dir', n<lastN); body.classList.remove('ktc-enter'); void body.offsetWidth; body.classList.add('ktc-enter');
        setTimeout(function(){body.classList.remove('ktc-enter');},400); var sp=scrollParent(head); if(sp)sp.scrollTop=0; }
      lastKey=key; lastN=n;
    }
    var dropT=findText(body,/^Choose photos or videos$/); if(dropT){ var d=dropT.closest('button,label')||dropT.parentElement&&dropT.parentElement.parentElement; if(d)d.classList.add('ktc-drop'); }
    var cov=findText(body,/^Cover$/); if(cov){ var g=cov; while(g&&g!==body&&getComputedStyle(g).display!=='grid')g=g.parentElement;
      if(g&&g!==body){ g.classList.add('ktc-grid'); for(var k=0;k<g.children.length;k++){ var c=g.children[k]; if(c.querySelector('img,video')){ c.classList.add('ktc-tile'); var md=c.querySelector('img,video'); var mb=md; while(mb.parentElement&&mb.parentElement!==c)mb=mb.parentElement; mb.classList.add('ktc-media'); } } } }
    var tp=findText(body,/^Tip:/i,'span,p,div'); if(tp){ var tb=tp.closest('div[class*=border]')||tp.parentElement; if(tb&&tb!==body)tb.classList.add('ktc-tip'); }
    var nt=findText(body,/(go live right away|checked before it goes live|community rules)/i,'span,p'); if(nt){ var box=nt.parentElement; if(box&&box!==body)box.classList.add('ktc-note'); }
  };

  // Cheskel (Oct 23 2026, 9:20 AM): every delete is red and asks first. Removing a photo, video, place or stop, and
  // leaving step 1 with something picked (that discards the post), show a sheet with a red action and Cancel.
  var bypass=false;
  var askSheet=function(msg,label,onYes){ haptic(); var ov=document.createElement('div'); ov.className='ktc-as-ov'; ov.setAttribute('role','dialog'); ov.setAttribute('aria-modal','true');
    var c1=document.createElement('div'); c1.className='ktc-as-card'; var m1=document.createElement('div'); m1.className='ktc-as-msg'; m1.textContent=msg;
    var yes=document.createElement('button'); yes.type='button'; yes.className='ktc-as-btn ktc-red'; yes.textContent=label; c1.appendChild(m1); c1.appendChild(yes);
    var no=document.createElement('button'); no.type='button'; no.className='ktc-as-btn ktc-cancel'; no.textContent='Cancel';
    ov.appendChild(c1); ov.appendChild(no); document.body.appendChild(ov);
    var close=function(){ if(ov.parentNode)ov.parentNode.removeChild(ov); };
    ov.addEventListener('click',function(e){ if(e.target===ov)close(); }); no.addEventListener('click',close);
    yes.addEventListener('click',function(){ close(); try{onYes();}catch(e){} }); };
  var replay=function(btn){ bypass=true; try{btn.click();}finally{bypass=false;} };
  document.addEventListener('click',function(e){ if(bypass)return; var t=e.target; if(!t||!t.closest)return;
    var head=document.querySelector('.ktc-head'); if(!head)return;
    var title=((document.querySelector('.ktc-title')||{}).textContent||'').trim();
    var btn=t.closest('button[aria-label="Remove"]');
    if(btn&&!btn.closest('.ktc-as-ov')){
      var tile=btn.closest('.ktc-tile')||btn.parentElement; var vid=tile&&tile.querySelector('video'), img=tile&&tile.querySelector('img');
      if(/^Edit/.test(title)&&(vid||img))return; // the edit screen asks itself
      e.preventDefault(); e.stopPropagation(); if(e.stopImmediatePropagation)e.stopImmediatePropagation();
      var what=vid?'video':img?'photo':'place'; askSheet(what==='place'?'Remove this place from your post?':'Remove this '+what+' from your post?', 'Remove '+what, function(){ replay(btn); });
      return; }
    var back=t.closest('.ktc-back');
    if(back&&lastN===1&&!/^Edit/.test(title)){ var body=document.querySelector('.ktc-body');
      var has=body&&(body.querySelector('.ktc-tile,button[aria-label="Remove"]')||Array.prototype.some.call(body.querySelectorAll('input[type=text],textarea'),function(x){return (x.value||'').trim().length>0;}));
      if(has){ e.preventDefault(); e.stopPropagation(); if(e.stopImmediatePropagation)e.stopImmediatePropagation();
        askSheet('Discard this post? What you picked will not be saved.','Discard',function(){ replay(back); }); } }
  },true);
  var q=false, sched=function(){ if(q)return; q=true; requestAnimationFrame(function(){ q=false; try{tag();}catch(e){} }); };
  var start=function(){ new MutationObserver(sched).observe(document.body,{childList:true,subtree:true,characterData:true}); sched();
    var vv=window.visualViewport; if(vv){ var kb=function(){ var h=Math.max(0, window.innerHeight - vv.height - vv.offsetTop); de.style.setProperty('--ktc-kb', (h>80?h:0)+'px'); };
      vv.addEventListener('resize',kb); vv.addEventListener('scroll',kb); } };
  if(document.body) start(); else document.addEventListener('DOMContentLoaded',start);
}catch(e){}})();
"""#
}
