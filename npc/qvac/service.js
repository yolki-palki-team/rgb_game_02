import http from 'node:http';import fs from 'node:fs';import path from 'node:path';import {fileURLToPath} from 'node:url';import crypto from 'node:crypto';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),STATE=path.join(ROOT,'.state/npc');
fs.mkdirSync(STATE,{recursive:true,mode:0o700});
const keyPath=path.join(STATE,'service.key');
if(!fs.existsSync(keyPath))fs.writeFileSync(keyPath,crypto.randomBytes(32).toString('hex'),{mode:0o600,flag:'wx'});
const token=fs.readFileSync(keyPath,'utf8').trim();
const configPath=path.join(STATE,'qvac.config.json');
fs.writeFileSync(configPath,JSON.stringify({cacheDirectory:path.join(STATE,'models'),loggerConsoleOutput:false,loggerLevel:'error',plugins:['llamacpp-completion'],httpDownloadConcurrency:3,httpConnectionTimeoutMs:10000}),{mode:0o600});
process.env.QVAC_CONFIG_PATH=configPath;
const {BlacksmithModel}=await import('./model.js');const model=new BlacksmithModel();
function respond(res,status,value){if(res.destroyed)return;const body=JSON.stringify(value);res.writeHead(status,{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body),'Cache-Control':'no-store'});res.end(body);}
function authorized(req){const expected=Buffer.from('Bearer '+token),actual=Buffer.from(req.headers.authorization||'');return expected.length===actual.length&&crypto.timingSafeEqual(expected,actual);}
async function body(req){let size=0,chunks=[];for await(const chunk of req){size+=chunk.length;if(size>24000)throw new Error('invalid_request');chunks.push(chunk);}return JSON.parse(Buffer.concat(chunks).toString());}
const server=http.createServer(async(req,res)=>{
 if(req.headers.origin)return respond(res,403,{error:'origin_not_allowed'});
 if(req.method==='GET'&&req.url==='/health')return respond(res,200,{application:'runeforge-blacksmith-qvac',...model.snapshot()});
 if(!authorized(req))return respond(res,401,{error:'unauthorized'});
 if(req.method==='POST'&&req.url==='/load'){void model.load().catch(()=>{});return respond(res,202,model.snapshot());}
 if(req.method!=='POST'||req.url!=='/reply')return respond(res,404,{error:'not_found'});
 const controller=new AbortController();res.on('close',()=>{if(!res.writableEnded)controller.abort();});
 try{
  const data=await body(req);
  if(!data||Object.keys(data).some(k=>!['request_id','facts','history','message'].includes(k))||typeof data.message!=='string'||!data.message.trim()||data.message.length>600||typeof data.request_id!=='string'||data.request_id.length>64||!data.facts||typeof data.facts!=='object'||!Array.isArray(data.history)||data.history.length>6||data.history.some(m=>!['user','assistant'].includes(m.role)||typeof m.content!=='string'||m.content.length>600))throw new Error('invalid_request');
  respond(res,200,await model.reply(data,controller.signal));
 }catch(error){const code=['model_not_ready','model_busy','inference_timeout','inference_incomplete','invalid_response','invalid_request'].includes(error.message)?error.message:'inference_failed';respond(res,code==='model_busy'?429:code==='invalid_request'?400:503,{error:code});}
});
server.listen(Number(process.env.RUNEFORGE_QVAC_PORT||8790),'127.0.0.1',()=>{console.log('RuneForge blacksmith QVAC service listening on loopback.');void model.load().catch(()=>{});});
let exiting=false;async function shutdown(){if(exiting)return;exiting=true;server.close();const timer=setTimeout(()=>process.exit(0),5000);timer.unref();await model.dispose().catch(()=>{});process.exit(0);}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
