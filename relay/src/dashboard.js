// Minimal debug map: shows what the relay is serving. Key is read from ?k= in the page URL.
export const DASHBOARD_HTML = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ares relay</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>html,body,#map{height:100%;margin:0;font:14px system-ui}#info{position:absolute;z-index:999;top:8px;right:8px;background:#fff;padding:8px;border-radius:6px;max-width:40%}</style>
</head><body><div id="map"></div><div id="info">loading…</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const k = new URLSearchParams(location.search).get('k') || '';
const map = L.map('map'); L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19}).addTo(map);
const layer = L.layerGroup().addTo(map); let fitted = false;
const color = (e) => e.kind===0 ? ['#22c55e','#6b7280','#ef4444','#eab308','#6b7280'][e.state] : e.kind===1 ? '#ef4444' : e.kind===2 ? ['#e5e7eb','#3b82f6','#ef4444','#f59e0b'][e.state] : '#a855f7';
async function refresh(){
  const r = await fetch('/v1/state?k='+encodeURIComponent(k)); if(!r.ok){info.textContent='HTTP '+r.status;return;}
  const s = await r.json(); layer.clearLayers(); const pts=[];
  for (const e of s.entities){ pts.push([e.lat,e.lon]); L.circleMarker([e.lat,e.lon],{radius:e.kind===2?10:7,color:color(e),fillOpacity:.8}).bindTooltip(e.label,{permanent:true}).addTo(layer); }
  if (s.viewer){ pts.push([s.viewer.lat,s.viewer.lon]); L.circleMarker([s.viewer.lat,s.viewer.lon],{radius:9,color:'#000',fillColor:'#fff',fillOpacity:1}).bindTooltip('WATCH').addTo(layer); }
  if (!fitted && pts.length){ map.fitBounds(pts,{padding:[30,30]}); fitted=true; }
  info.innerHTML = 'seq '+s.seq+' · '+s.entities.length+' entities'+(s.viewer?'<br>watch seen '+Math.round((Date.now()-s.viewer.at)/1000)+'s ago':'<br>watch not seen yet')+'<hr>'+s.messages.map(m=>m.text).join('<br>');
}
map.setView([0,0],2); refresh(); setInterval(refresh,2000);
</script></body></html>`;
