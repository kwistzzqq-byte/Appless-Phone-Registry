import { HtmlHomeBlock, HtmlHomeDocument, HtmlHomeMetric } from './HtmlHomeTypes';

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function metricValue(block: HtmlHomeBlock, label: string): string {
  const rows: HtmlHomeMetric[] = block.metrics.concat(block.rows);
  for (let index = 0; index < rows.length; index++) {
    if (rows[index].label.toLowerCase() === label.toLowerCase()) return rows[index].value.trim();
  }
  return '';
}

function registryStatusBlock(document: HtmlHomeDocument): HtmlHomeBlock | null {
  for (let index = 0; index < document.blocks.length; index++) {
    const block = document.blocks[index];
    if (block.kind === 'generic-tool-result' && metricValue(block, 'toolName') === 'registry.status') {
      return block;
    }
  }
  return null;
}

function onlineDevices(block: HtmlHomeBlock): string[] {
  const devices: string[] = [];
  for (let index = 0; index < block.rows.length; index++) {
    const row = block.rows[index];
    if (row.label.indexOf('在线设备 ') !== 0) continue;
    const serviceId = row.value.trim();
    if (serviceId.length === 0 || devices.indexOf(serviceId) >= 0) continue;
    devices.push(serviceId);
  }
  return devices;
}

export function shouldRenderRegistryDevicesHomeDocument(document: HtmlHomeDocument): boolean {
  return registryStatusBlock(document) !== null;
}

export function renderRegistryDevicesHomeDocument(
  document: HtmlHomeDocument,
  isBusy: boolean = false
): string {
  const block = registryStatusBlock(document);
  const devices = block === null ? [] : onlineDevices(block);
  return [
    '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" />',
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />',
    '<title>注册中心在线设备</title><style>', REGISTRY_DEVICES_CSS, '</style></head><body>',
    '<main class="registry-shell"><section class="registry-panel">',
    '<header class="registry-header"><div class="eyebrow">在线设备</div>',
    '<h1>注册中心返回的设备列表</h1></header>',
    '<label class="search-wrap"><span class="sr-only">搜索设备</span>',
    '<input id="device-search" type="search" value="在线设备" aria-label="搜索设备" ',
    isBusy ? 'disabled ' : '', '/></label>',
    devices.length === 0 ? renderEmptyState() : '<div id="device-list" class="device-list">' +
      devices.map((serviceId: string, index: number): string =>
        renderDevice(serviceId, index, isBusy)).join('') + '</div>',
    '</section></main><script>', REGISTRY_DEVICES_SCRIPT,
    '</script></body></html>'
  ].join('');
}

function renderDevice(serviceId: string, index: number, isBusy: boolean): string {
  return [
    '<article class="device-row', index === 0 ? ' is-active' : '', '" tabindex="0" data-device="',
    escapeHtml(serviceId), '"><div class="device-copy"><div class="device-name-line"><h2>',
    escapeHtml(serviceId), '</h2><span class="status-pill">在线</span></div></div>',
    '<button class="chat-button', index === 0 ? ' primary' : '', '" type="button" data-chat-target="',
    escapeHtml(serviceId), '"', isBusy ? ' disabled' : '', '>进入对话</button></article>'
  ].join('');
}

function renderEmptyState(): string {
  return '<div class="empty-state"><div class="eyebrow">空结果</div>' +
    '<h2>当前没有其他在线设备</h2><p>注册中心连通正常，但此刻没有可直接发起会话的 Agent。</p></div>';
}

const REGISTRY_DEVICES_CSS: string = `
:root{color-scheme:light;--paper:#f5f2ee;--panel:#fffdf9;--ink:#211b17;--muted:#7a6e64;--line:#e7dfd6;--blue:#995f4c;--blue-soft:#f8efeb;--green:#2f7754;--green-soft:#e4f1e8}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}body{margin:0;min-height:100dvh;background:var(--paper);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"HarmonyOS Sans SC","PingFang SC",sans-serif;-webkit-font-smoothing:antialiased}
button,input{font:inherit}.registry-shell{width:min(100%,760px);margin:0 auto;padding:16px 14px calc(96px + env(safe-area-inset-bottom,0px))}.registry-panel{border:1px solid var(--line);border-radius:24px;padding:18px;background:rgba(255,253,249,.94);box-shadow:0 10px 28px rgba(44,34,26,.06)}
.registry-header{margin-bottom:16px}.eyebrow{color:var(--muted);font-size:12px;line-height:1.35;letter-spacing:.06em}.registry-header h1{margin:7px 0 0;font-size:25px;line-height:1.16;font-weight:800;letter-spacing:-.02em}.search-wrap{display:block;margin-bottom:16px}.search-wrap input{width:100%;min-height:46px;border:1px solid var(--line);border-radius:14px;padding:0 15px;background:#f8f5f0;color:var(--ink);outline:none}.search-wrap input:focus{border-color:rgba(153,95,76,.6);box-shadow:0 0 0 3px rgba(153,95,76,.12)}
.device-list{display:grid;gap:12px}.device-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:14px;align-items:center;border:1px solid var(--line);border-radius:18px;padding:16px;background:#fff;transition:border-color 160ms ease,background-color 160ms ease,transform 160ms ease}.device-row:active{transform:scale(.992)}.device-row.is-active{border-color:rgba(153,95,76,.42);background:var(--blue-soft)}
.device-copy{min-width:0}.device-name-line{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.device-name-line h2{min-width:0;margin:0;overflow-wrap:anywhere;font-size:18px;line-height:1.25;font-weight:760}.status-pill{display:inline-flex;align-items:center;width:max-content;border-radius:999px;min-height:27px;border:1px solid rgba(47,119,84,.28);padding:3px 9px;background:var(--green-soft);font-size:12px}.status-pill:before{content:"";width:7px;height:7px;margin-right:7px;border-radius:50%;background:var(--green)}
.chat-button{min-height:42px;border:1px solid rgba(153,95,76,.34);border-radius:12px;padding:0 14px;background:#fffdf9;color:var(--ink);font-size:13px;font-weight:700}.chat-button.primary{border-color:var(--blue);background:var(--blue);color:#fff}.chat-button:disabled{opacity:.5}.empty-state{border:1px solid var(--line);border-radius:18px;padding:22px;background:#fff}.empty-state h2{margin:7px 0 0;font-size:19px}.empty-state p{margin:9px 0 0;color:var(--muted);font-size:13px;line-height:1.55}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
@media(max-width:520px){.registry-shell{padding:14px 12px calc(92px + env(safe-area-inset-bottom,0px))}.registry-panel{padding:16px;border-radius:22px}.registry-header h1{font-size:23px}.device-row{grid-template-columns:1fr;padding:16px}.chat-button{width:max-content;min-width:104px}.device-name-line h2{font-size:17px}}
@media(prefers-reduced-motion:reduce){*{transition:none!important}}
`;

const REGISTRY_DEVICES_SCRIPT: string = `
(function(){
  var rows=Array.prototype.slice.call(document.querySelectorAll('.device-row'));
  var buttons=Array.prototype.slice.call(document.querySelectorAll('[data-chat-target]'));
  function select(row){
    rows.forEach(function(item){item.classList.toggle('is-active',item===row);});
    buttons.forEach(function(button){button.classList.toggle('primary',button.closest('.device-row')===row);});
  }
  rows.forEach(function(row){
    row.addEventListener('click',function(){select(row);});
    row.addEventListener('keydown',function(event){if(event.key==='Enter'||event.key===' '){event.preventDefault();select(row);}});
  });
  buttons.forEach(function(button){button.addEventListener('click',function(event){
    event.stopPropagation();var target=button.getAttribute('data-chat-target')||'';var row=button.closest('.device-row');if(row){select(row);}
    if(!target||!window.AIPhoneHome||!AIPhoneHome.postAction){return;}
    AIPhoneHome.postAction(JSON.stringify({id:'registry.device.chat',label:'进入对话',prompt:'',variant:'primary',kind:'client',args:{serviceId:target}}));
  });});
  var search=document.getElementById('device-search');
  if(search){search.addEventListener('input',function(){var query=(search.value||'').trim().toLowerCase();rows.forEach(function(row){var name=(row.getAttribute('data-device')||'').toLowerCase();row.hidden=query.length>0&&query!=='在线设备'&&name.indexOf(query)<0;});});}
})();
`;
