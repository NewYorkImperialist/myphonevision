"""Live tuning page for the phone sword game, served by the bridge at http://localhost:8765.

Shows each controller's direction live (top and side views) and lets you turn it in its
own axes (yaw, pitch, roll) while playing, plus a button that asks the phone to line both
blades up with where the player is looking (same as triple-clicking A).
"""
from __future__ import annotations

import json
import math
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import quat as Q

PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>Sword game tuner</title>
<style>
body{font:15px system-ui,sans-serif;background:#0b0d16;color:#dde;margin:16px}
h1{font-size:18px;margin:0 0 12px}.hands{display:flex;gap:16px;flex-wrap:wrap}
.hand{background:#151a2b;border-radius:10px;padding:12px;width:430px}
.hand h2{margin:0 0 8px;font-size:16px}.views{display:flex;gap:8px}
canvas{background:#0b0d16;border-radius:6px}label{display:flex;align-items:center;gap:8px;margin:6px 0}
label span{width:44px}input[type=range]{flex:1}b{display:inline-block;width:48px;text-align:right}
button{background:#2b3a66;color:#fff;border:0;border-radius:6px;padding:7px 10px;margin:4px 4px 0 0;cursor:pointer}
button.big{background:#3a7bd5;font-size:16px;padding:10px 16px}.stat{color:#9ab;font-size:13px;margin-top:6px}
</style></head><body>
<h1>Sword game tuner <button class="big" onclick="post('/realign',{})">Realign blades (point controllers forward)</button></h1>
<div class="hands" id="hands"></div>
<script>
const names=["Left","Right"],colors=["#3b8cff","#ff5a2a"];
const H=document.getElementById("hands");
for(let h=0;h<2;h++){H.insertAdjacentHTML("beforeend",`<div class="hand"><h2 style="color:${colors[h]}">${names[h]} controller</h2>
<div class="views"><div><canvas id="top${h}" width="200" height="200"></canvas><div class="stat">from above (up = forward)</div></div>
<div><canvas id="side${h}" width="200" height="200"></canvas><div class="stat">from the side (left = forward)</div></div></div>
${["yaw","pitch","roll"].map(k=>`<label><span>${k}</span><input type="range" min="-180" max="180" step="5" id="${k}${h}" oninput="send(${h})"><b id="${k}v${h}">0</b></label>`).join("")}
<button onclick="bump(${h},'pitch',180)">Flip (pitch 180)</button><button onclick="bump(${h},'yaw',180)">Turn around (yaw 180)</button>
<button onclick="bump(${h},'roll',180)">Roll 180</button><button onclick="zero(${h})">Reset</button>
<div class="stat" id="stat${h}">waiting...</div></div>`)}
function post(u,b){return fetch(u,{method:"POST",body:JSON.stringify(b)})}
function wrap(a){a=((a+180)%360+360)%360-180;return a}
function send(h){const o={hand:h};for(const k of["yaw","pitch","roll"]){o[k]=+document.getElementById(k+h).value;document.getElementById(k+"v"+h).textContent=o[k]}post("/set",o)}
function bump(h,k,d){const e=document.getElementById(k+h);e.value=wrap(+e.value+d);send(h)}
function zero(h){for(const k of["yaw","pitch","roll"])document.getElementById(k+h).value=0;send(h)}
function arrow(c,x,y,col){const g=c.getContext("2d");g.clearRect(0,0,200,200);g.strokeStyle="#334";g.beginPath();g.arc(100,100,80,0,7);g.moveTo(100,15);g.lineTo(100,185);g.moveTo(15,100);g.lineTo(185,100);g.stroke();
g.strokeStyle=col;g.lineWidth=5;g.beginPath();g.moveTo(100,100);g.lineTo(100+x*80,100+y*80);g.stroke();g.fillStyle=col;g.beginPath();g.arc(100+x*80,100+y*80,6,0,7);g.fill();g.lineWidth=1}
let first=true;
async function tick(){try{const s=await (await fetch("/state")).json();
for(let h=0;h<2;h++){const d=s.hands[h];if(first){for(const k of["yaw","pitch","roll"]){document.getElementById(k+h).value=s.offsets[h][k];document.getElementById(k+"v"+h).textContent=s.offsets[h][k]}}
if(!d||d.age>0.5){document.getElementById("stat"+h).textContent="no data (controller off?)";continue}
const f=d.forward;arrow(document.getElementById("top"+h),f[0],f[2],colors[h]);arrow(document.getElementById("side"+h),f[2],-f[1],colors[h]);
const pitch=Math.round(Math.asin(Math.max(-1,Math.min(1,f[1])))*180/Math.PI);
document.getElementById("stat"+h).textContent=`${d.rate} Hz · blade points ${pitch>=0?"up":"down"} ${Math.abs(pitch)}° · A ${d.a?"down":"up"}`}
first=false}catch(e){}setTimeout(tick,100)}
tick();
</script></body></html>"""


class Tuner:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.offsets = {0: {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}, 1: {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}}
        self.latest: dict[int, dict] = {}
        self.stamps: dict[int, list[float]] = {0: [], 1: []}
        self.realign_until = 0.0

    def apply(self, hand: int, rot: Q.Quat) -> Q.Quat:
        """The controller's rotation turned by this hand's offsets, in its own axes."""
        with self.lock:
            o = dict(self.offsets[hand])
        q = Q.axis_angle((0.0, 1.0, 0.0), math.radians(o["yaw"]))
        q = Q.mul(q, Q.axis_angle((1.0, 0.0, 0.0), math.radians(o["pitch"])))
        q = Q.mul(q, Q.axis_angle((0.0, 0.0, 1.0), math.radians(o["roll"])))
        return Q.normalize(Q.mul(rot, q))

    def record(self, hand: int, rot: Q.Quat, a_down: bool) -> None:
        now = time.monotonic()
        with self.lock:
            st = [t for t in self.stamps[hand] if now - t < 1.0] + [now]
            self.stamps[hand] = st
            self.latest[hand] = {"forward": Q.rotate(rot, (0.0, 0.0, -1.0)), "t": now, "rate": len(st), "a": a_down}

    def realign_bit(self) -> int:
        """Bit 2 of the phone packet's buttons while a realign request is fresh."""
        return 4 if time.monotonic() < self.realign_until else 0

    def state(self) -> dict:
        now = time.monotonic()
        with self.lock:
            hands = [None, None]
            for h, d in self.latest.items():
                hands[h] = {"forward": d["forward"], "age": now - d["t"], "rate": d["rate"], "a": d["a"]}
            return {"hands": hands, "offsets": [self.offsets[0], self.offsets[1]]}

    def serve(self, port: int = 8765) -> None:
        tuner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args) -> None:  # keep the bridge's console quiet
                pass

            def _send(self, body: bytes, kind: str) -> None:
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:
                if self.path.startswith("/state"):
                    self._send(json.dumps(tuner.state()).encode(), "application/json")
                else:
                    self._send(PAGE.encode(), "text/html; charset=utf-8")

            def do_POST(self) -> None:
                n = int(self.headers.get("Content-Length") or 0)
                try:
                    data = json.loads(self.rfile.read(n) or b"{}")
                except ValueError:
                    data = {}
                if self.path.startswith("/set") and data.get("hand") in (0, 1):
                    with tuner.lock:
                        for k in ("yaw", "pitch", "roll"):
                            if k in data:
                                tuner.offsets[data["hand"]][k] = float(data[k])
                elif self.path.startswith("/realign"):
                    tuner.realign_until = time.monotonic() + 0.4
                self._send(b"{}", "application/json")

        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"Tuner page: http://localhost:{port}")
