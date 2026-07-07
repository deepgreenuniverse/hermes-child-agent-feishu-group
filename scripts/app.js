const agents = [];
let currentIndex = 0;
let pollCount = 0;
const S = {PENDING:'pending',WAITING:'waiting_scan',POLLING:'polling',DONE:'done',ERROR:'error'};

function log(msg, type=''){
  const box=document.getElementById('logBox');
  const ts=new Date().toLocaleTimeString();
  const cls=type==='ok'?'log-ok':type==='err'?'log-err':type==='info'?'log-info':'';
  box.innerHTML+=`<div class="log-line"><span class="log-ts">[${ts}]</span><span class="${cls}">${esc(msg)}</span></div>`;
  box.scrollTop=box.scrollHeight;
}
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function renderCard(i){
  const a=agents[i];
  const card=document.getElementById('card-'+i);
  if(!card)return;
  const stateLabel={pending:'等待中',waiting_scan:'等待扫码',polling:'授权中...',done:'✅ 完成',error:'❌ 失败'}[a.state]||a.state;
  card.className='agent-card '+(a.state===S.WAITING?'active':a.state===S.DONE?'done':a.state===S.ERROR?'error':'');
  card.querySelector('.agent-status').className='agent-status status-'+a.state;
  card.querySelector('.agent-status').textContent=stateLabel;
  const qr=card.querySelector('.qr-box');
  const creds=card.querySelector('.agent-creds');
  const err=card.querySelector('.error-msg');
  if(a.state===S.WAITING||a.state===S.POLLING){
    qr.style.display='block';
    qr.innerHTML=`<div class="qr-hint">${a.state===S.WAITING?'用飞书扫码确认创建':'⏳ 等待创建确认... 轮询中 ('+pollCount+')'}</div>
      <div class="user-code">${a.userCode||''}</div>
      <a href="https://open.feishu.cn/page/launcher?user_code=${a.userCode||''}" target="_blank">👉 点击打开飞书授权页</a>
      <div class="qr-hint">设备码: ${(a.deviceCode||'').substring(0,20)}...</div>`;
    creds.style.display='none';err.style.display='none';
  }else if(a.state===S.DONE){
    qr.style.display='none';creds.style.display='block';
    creds.innerHTML=`<div><span>app_id:</span> ${a.appId||''}</div><div><span>app_secret:</span> ${a.appSecret||''}</div>`;
    err.style.display='none';
  }else if(a.state===S.ERROR){
    qr.style.display='none';creds.style.display='none';err.style.display='block';err.textContent=a.error||'未知错误';
  }else{qr.style.display='none';creds.style.display='none';err.style.display='none';}
}

function copyResults(){
  const text=document.getElementById('resultsText').value;
  if(!text)return;
  navigator.clipboard.writeText(text).then(()=>log('✅ 凭证已复制到剪贴板','ok')).catch(()=>log('❌ 复制失败','err'));
}

function renderAll(){
  for(let i=0;i<agents.length;i++)renderCard(i);
  const done=agents.filter(a=>a.state===S.DONE).length;
  document.getElementById('progressInfo').textContent=agents.length?`已完成 ${done}/${agents.length}`:'';
  const doneAgents=agents.filter(a=>a.state===S.DONE&&a.appId&&a.appSecret);
  const section=document.getElementById('resultsSection');
  const ta=document.getElementById('resultsText');
  if(doneAgents.length){
    section.style.display='block';
    ta.value=doneAgents.map(a=>`【${a.name}】\nappId=${a.appId}\nappSecret=${a.appSecret}`).join('\n\n');
  }
}

async function api(method,path,body){
  const opts={method,headers:{'Content-Type':'application/json'}};
  if(body)opts.body=JSON.stringify(body);
  const r=await fetch(path,opts);
  return r.json();
}

async function startBatch(){
  const text=document.getElementById('agentNames').value.trim();
  if(!text){alert('请输入至少一个 Agent 名称');return;}
  const names=text.split('\n').map(n=>n.trim()).filter(Boolean);
  if(!names.length)return;
  agents.splice(0,agents.length);
  names.forEach(name=>agents.push({name,state:S.PENDING,deviceCode:null,userCode:null,appId:null,appSecret:null,error:null}));
  currentIndex=0;
  const grid=document.getElementById('agentsGrid');
  grid.innerHTML=agents.map((a,i)=>`<div class="agent-card" id="card-${i}"><div class="agent-name">${esc(a.name)}</div><span class="agent-status status-pending">等待中</span><div class="qr-box" style="display:none"></div><div class="agent-creds" style="display:none"></div><div class="error-msg" style="display:none"></div></div>`).join('');
  document.getElementById('btnStart').disabled=true;
  log(`批次开始，共 ${names.length} 个 Agent`,'info');
  renderAll();
  await processNext();
}

async function processNext(){
  if(currentIndex>=agents.length){log('✅ 全部完成！','ok');document.getElementById('btnStart').disabled=false;return;}
  const a=agents[currentIndex];
  log(`\n[${a.name}] 开始第 ${currentIndex+1}/${agents.length} 个`);
  try{
    const d=await api('POST','/feishu/begin',{});
    if(d.error)throw new Error(d.error_description||d.error);
    a.deviceCode=d.device_code;a.userCode=d.user_code;a.state=S.WAITING;
    log(`[${a.name}] 授权码: ${a.userCode}`);
    log(`[${a.name}] 链接: https://open.feishu.cn/page/launcher?user_code=${a.userCode}`,'info');
    renderAll();pollCount=0;pollLoop();
  }catch(e){a.state=S.ERROR;a.error=e.message;log(`[${a.name}] ❌ ${e.message}`,'err');renderAll();currentIndex++;await processNext();}
}

async function pollLoop(){
  if(currentIndex>=agents.length)return;
  const a=agents[currentIndex];
  if(a.state!==S.WAITING&&a.state!==S.POLLING)return;
  a.state=S.POLLING;pollCount++;renderAll();
  try{
    const d=await api('POST','/feishu/poll',{device_code:a.deviceCode});
    if(d.client_id&&d.client_secret){a.appId=d.client_id;a.appSecret=d.client_secret;a.state=S.DONE;log(`[${a.name}] ✅ 创建成功！app_id: ${a.appId}`,'ok');log(`[${a.name}] app_secret: ${a.appSecret}`,'ok');renderAll();currentIndex++;await processNext();return;}
    if(d.error&&d.error!=='authorization_pending'){throw new Error(d.error_description||d.error);}
  }catch(e){a.state=S.ERROR;a.error=e.message;log(`[${a.name}] ❌ ${e.message}`,'err');renderAll();currentIndex++;await processNext();return;}
  setTimeout(pollLoop,5000);
}

function resetAll(){agents.splice(0,agents.length);currentIndex=0;document.getElementById('agentsGrid').innerHTML='';document.getElementById('logBox').innerHTML='';document.getElementById('progressInfo').textContent='';document.getElementById('resultsSection').style.display='none';document.getElementById('resultsText').value='';document.getElementById('btnStart').disabled=false;}
