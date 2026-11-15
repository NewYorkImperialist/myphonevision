"""Live tuning page for the phone sword game, served by the bridge at http://localhost:8765.

- A live view of what the player sees, drawn from the game state the phone sends back
  (UDP 39602: b"MPVS", head position/forward/up, then the phone's scene floats).
- Per controller: Calibrate (point it straight up and click: the bridge works out which
  way its blade really points, whatever the mounting), fine-tune sliders, and a live
  arrow of where the blade points.
- Realign: asks the phone to line both blades up with where the player looks.
"""
from __future__ import annotations

import json
import math
import os
import socket
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import quat as Q

SPECTATOR_PORT = 39602
SAVE = os.path.expanduser("~/.myphonevision-tuner.json")   # calibration and sliders survive bridge restarts
ZERO = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "height": 0.0, "forward": 0.0, "side": 0.0}

PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>Sword game tuner</title>
<style>
body{font:15px system-ui,sans-serif;background:#0b0d16;color:#dde;margin:16px}
h1{font-size:18px;margin:0 0 10px}.row{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-start}
#view{background:#05060c;border-radius:10px;width:960px;max-width:100%;aspect-ratio:16/9}
.hand{background:#151a2b;border-radius:10px;padding:12px;width:430px}
.hand h2{margin:0 0 8px;font-size:16px}.views{display:flex;gap:8px}
canvas.small{background:#0b0d16;border-radius:6px}label{display:flex;align-items:center;gap:8px;margin:6px 0}
label span{width:44px}input[type=range]{flex:1}b{display:inline-block;width:48px;text-align:right}
button{background:#2b3a66;color:#fff;border:0;border-radius:6px;padding:7px 10px;margin:4px 4px 0 0;cursor:pointer}
button.big{background:#3a7bd5;font-size:16px;padding:10px 16px}button.scn{background:#5a3a8a}button.scare{background:#c0101a;font-size:22px;font-weight:800;padding:14px 28px;letter-spacing:2px}button.cal{background:#1f8a5b;font-size:15px}
.stat{color:#9ab;font-size:13px;margin-top:6px}.steps{color:#bcd;margin:6px 0 12px}
</style></head><body>
<h1>Sword game admin</h1>
<div id="status" class="steps">connecting...</div>
<div class="steps">
<button class="cal big" onclick="post('/calibrate',{hand:0});post('/calibrate',{hand:1})">Calibrate both (held straight up)</button>
<button class="cal" onclick="countdown()" id="cd">Calibrate both in 3 s</button>
<button class="big" onclick="post('/realign',{})">Realign blades (pointing forward)</button>
<button onclick="post('/command',{cmd:1})">Recenter play area</button>
<button onclick="post('/command',{cmd:2})">Reset score</button>
</div>
<div class="steps"><button class="scare" onclick="post('/command',{cmd:30})">JUMPSCARE</button></div>
<div class="steps"><b style="width:auto">Scene:</b>
<button class="scn" onclick="post('/command',{cmd:10})">Neon grid</button><button class="scn" onclick="post('/command',{cmd:11})">Forest</button>
<button class="scn" onclick="post('/command',{cmd:12})">Space</button><button class="scn" onclick="post('/command',{cmd:13})">Moon</button>
<button class="scn" onclick="post('/command',{cmd:14})">Volcano</button>
&nbsp; <b style="width:auto">Mode:</b>
<button class="scn" onclick="post('/command',{cmd:20})">Sword game</button><button class="scn" onclick="post('/command',{cmd:21})">Explore (no cubes)</button>
</div>
<div class="row"><canvas id="view" width="1280" height="720"></canvas><div id="hands"></div></div>
<script>
const names=["Left","Right"],colors=["#3b8cff","#ff5a2a"];
const H=document.getElementById("hands");
for(let h=0;h<2;h++){H.insertAdjacentHTML("beforeend",`<div class="hand" style="margin-bottom:12px"><h2 style="color:${colors[h]}">${names[h]} controller</h2>
<button class="cal" onclick="post('/calibrate',{hand:${h}})">Calibrate (pointing straight up)</button>
<div class="views"><div><canvas class="small" id="top${h}" width="190" height="190"></canvas><div class="stat">from above (up = forward)</div></div>
<div><canvas class="small" id="side${h}" width="190" height="190"></canvas><div class="stat">from the side (left = forward)</div></div></div>
${["yaw","pitch","roll"].map(k=>`<label><span>${k}</span><input type="range" min="-180" max="180" step="5" id="${k}${h}" oninput="send(${h})"><b id="${k}v${h}">0</b></label>`).join("")}
${["height","forward","side"].map(k=>`<label><span>${k}</span><input type="range" min="-50" max="50" step="1" id="${k}${h}" oninput="send(${h})"><b id="${k}v${h}">0</b></label>`).join("")}
<button onclick="bump(${h},'pitch',180)">Flip</button><button onclick="bump(${h},'yaw',180)">Turn around</button><button onclick="zero(${h})">Reset</button>
<div class="stat" id="stat${h}">waiting...</div></div>`)}
function post(u,b){return fetch(u,{method:"POST",body:JSON.stringify(b)})}
function wrap(a){return((a+180)%360+360)%360-180}
const KEYS=["yaw","pitch","roll","height","forward","side"];
function send(h){const o={hand:h};for(const k of KEYS){o[k]=+document.getElementById(k+h).value;document.getElementById(k+"v"+h).textContent=o[k]+(["height","forward","side"].includes(k)?" cm":"°")}post("/set",o)}
function countdown(){const b=document.getElementById("cd");let n=3;b.textContent="Hold them up... "+n;const t=setInterval(()=>{n--;if(n>0){b.textContent="Hold them up... "+n}else{clearInterval(t);post('/calibrate',{hand:0});post('/calibrate',{hand:1});b.textContent="Calibrated!";setTimeout(()=>b.textContent="Calibrate both in 3 s",1500)}},1000)}
function bump(h,k,d){const e=document.getElementById(k+h);e.value=wrap(+e.value+d);send(h)}
function zero(h){for(const k of KEYS)document.getElementById(k+h).value=0;send(h);post('/uncalibrate',{hand:h})}
function arrow(c,x,y,col){const g=c.getContext("2d"),s=c.width/2;g.clearRect(0,0,c.width,c.height);g.strokeStyle="#334";g.beginPath();g.arc(s,s,s*0.8,0,7);g.moveTo(s,8);g.lineTo(s,c.height-8);g.moveTo(8,s);g.lineTo(c.width-8,s);g.stroke();
g.strokeStyle=col;g.lineWidth=5;g.beginPath();g.moveTo(s,s);g.lineTo(s+x*s*0.8,s+y*s*0.8);g.stroke();g.fillStyle=col;g.beginPath();g.arc(s+x*s*0.8,s+y*s*0.8,6,0,7);g.fill();g.lineWidth=1}
// ---- live view: the player's eye, drawn from the phone's game state ----
const V=document.getElementById("view"),G=V.getContext("2d");
const sub=(a,b)=>[a[0]-b[0],a[1]-b[1],a[2]-b[2]],dot=(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const norm=a=>{const l=Math.hypot(...a)||1;return[a[0]/l,a[1]/l,a[2]/l]};
function rgb(c,k=1){return `rgb(${Math.min(255,c[0]*255*k)|0},${Math.min(255,c[1]*255*k)|0},${Math.min(255,c[2]*255*k)|0})`}
function drawScene(s){const W=V.width,Hh=V.height,F=(W/2)/Math.tan(50*Math.PI/180);
const eye=s.head.pos,f=norm(s.head.fwd),r=norm(cross(f,s.head.up)),u=cross(r,f);
const P=p=>{const d=sub(p,eye),z=dot(d,f);return z<0.05?null:[W/2+dot(d,r)/z*F,Hh/2-dot(d,u)/z*F,z]};
const seg=(a,b)=>{let pa=sub(a,eye),pb=sub(b,eye),za=dot(pa,f),zb=dot(pb,f);if(za<0.05&&zb<0.05)return null;
 if(za<0.05){const t=(0.05-za)/(zb-za);a=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t]}
 if(zb<0.05){const t=(0.05-zb)/(za-zb);b=[b[0]+(a[0]-b[0])*t,b[1]+(a[1]-b[1])*t,b[2]+(a[2]-b[2])*t]}return[P(a),P(b)]};
const SKY=[["#04040a","#1a1030","#05060c"],["#6f9fd0","#9cb98a","#2f4a22"],["#000","#05050c","#000"],["#000","#111","#6a6a66"],["#120404","#5a1606","#1a0805"],["#d8cdb8","#c8b89a","#6a4528"]][s.scene_id]||["#04040a","#1a1030","#05060c"];
const sky=G.createLinearGradient(0,0,0,Hh);sky.addColorStop(0,SKY[0]);sky.addColorStop(0.5,SKY[1]);sky.addColorStop(1,SKY[2]);G.fillStyle=sky;G.fillRect(0,0,W,Hh);
G.lineWidth=1;G.strokeStyle="rgba(60,100,200,0.35)";G.beginPath();const gx=Math.round(eye[0]),gz=Math.round(eye[2]);
for(let i=-8;i<=8;i++){for(const [a,b] of [[[gx+i*0.5,0,gz-4],[gx+i*0.5,0,gz+4]],[[gx-4,0,gz+i*0.5],[gx+4,0,gz+i*0.5]]]){const q=seg(a,b);if(q){G.moveTo(q[0][0],q[0][1]);G.lineTo(q[1][0],q[1][1])}}}G.stroke();
const boxes=s.boxes.map(b=>({...b,z:dot(sub(b.c,eye),f)})).sort((a,b)=>b.z-a.z);
for(const b of boxes){const corners=[];for(const sx of[-1,1])for(const sy of[-1,1])for(const sz of[-1,1])corners.push([0,1,2].map(i=>b.c[i]+b.ax[0][i]*sx+b.ax[1][i]*sy+b.ax[2][i]*sz));
 const E=[[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]];G.shadowColor=rgb(b.col);G.shadowBlur=14;G.strokeStyle=rgb(b.col,1.4);G.lineWidth=2.5;G.beginPath();
 for(const [i,j] of E){const q=seg(corners[i],corners[j]);if(q){G.moveTo(q[0][0],q[0][1]);G.lineTo(q[1][0],q[1][1])}}G.stroke();G.shadowBlur=0}
for(const bl of s.blades){if(!bl.valid)continue;const q=seg(bl.a,bl.b);if(!q)continue;G.lineCap="round";
 G.shadowColor=rgb(bl.col);G.shadowBlur=25;G.strokeStyle=rgb(bl.col);G.lineWidth=14;G.beginPath();G.moveTo(q[0][0],q[0][1]);G.lineTo(q[1][0],q[1][1]);G.stroke();
 G.shadowBlur=0;G.strokeStyle="#fff";G.lineWidth=5;G.beginPath();G.moveTo(q[0][0],q[0][1]);G.lineTo(q[1][0],q[1][1]);G.stroke()}
G.fillStyle="#9fe6ff";G.font="bold 44px system-ui";G.textAlign="center";if(s.mode_id==0)G.fillText(String(s.score),W/2,60);if(s.combo>1){G.font="24px system-ui";G.fillText("combo x"+s.combo,W/2,92)}}
function noView(msg){G.fillStyle="#05060c";G.fillRect(0,0,V.width,V.height);G.fillStyle="#789";G.font="28px system-ui";G.textAlign="center";G.fillText(msg,V.width/2,V.height/2)}
let first=true;
async function tick(){try{const s=await (await fetch("/state")).json();
if(s.scene&&s.scene.age<1)drawScene(s.scene);else noView("Waiting for the phone (start the sword game)");
for(let h=0;h<2;h++){const d=s.hands[h];if(first){for(const k of KEYS){document.getElementById(k+h).value=s.offsets[h][k]||0;document.getElementById(k+"v"+h).textContent=(s.offsets[h][k]||0)}}
if(!d||d.age>0.5){document.getElementById("stat"+h).textContent="no data (controller off?)";continue}
const fw=d.forward;arrow(document.getElementById("top"+h),fw[0],fw[2],colors[h]);arrow(document.getElementById("side"+h),fw[2],-fw[1],colors[h]);
const pitch=Math.round(Math.asin(Math.max(-1,Math.min(1,fw[1])))*180/Math.PI);
document.getElementById("stat"+h).innerHTML=`${d.rate} Hz · blade ${pitch>=0?"up":"down"} ${Math.abs(pitch)}° · ${d.calibrated?"calibrated":"<b style='color:#fb4;width:auto'>NOT calibrated</b>"} · A ${d.a?"down":"up"}${d.gyro?"":" · <b style='color:#f66;width:auto'>gyro drifting: power-cycle it held still</b>"}`}
const ph=s.scene&&s.scene.age<1,ok=h=>s.hands[h]&&s.hands[h].age<0.5;
const SN=["Neon grid","Forest","Space","Moon","Volcano","Study"],MN=["Sword game","Explore"];
document.getElementById("status").innerHTML=`Phone: ${ph?"<b style='color:#5d5;width:auto'>connected</b> · "+(SN[s.scene.scene_id]||"?")+" · "+(MN[s.scene.mode_id]||"?"):"<b style='color:#f66;width:auto'>no game data</b>"} &nbsp; Left: ${ok(0)?s.hands[0].rate+" Hz":"off"} &nbsp; Right: ${ok(1)?s.hands[1].rate+" Hz":"off"}`;
first=false}catch(e){}setTimeout(tick,33)}
tick();
</script></body></html>"""


def _from_to(a: Q.Vec, b: Q.Vec) -> Q.Quat:
    """Shortest rotation taking unit vector a to unit vector b."""
    d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    if d < -0.9999:
        return Q.axis_angle((1.0, 0.0, 0.0), math.pi)
    c = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    return Q.normalize((1.0 + d, c[0], c[1], c[2]))


class Tuner:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.offsets = {0: dict(ZERO), 1: dict(ZERO)}
        self.base: dict[int, Q.Quat] = {0: Q.IDENTITY, 1: Q.IDENTITY}   # from Calibrate
        self.calibrated = {0: False, 1: False}
        self.command_id, self.command_seq = 0, 0   # one-shot commands for the phone (1 recenter play area, 2 reset score)
        self.load()
        self.raw: dict[int, Q.Quat] = {}
        self.latest: dict[int, dict] = {}
        self.stamps: dict[int, list[float]] = {0: [], 1: []}
        self.realign_until = 0.0
        self.scene: dict | None = None
        self.scene_t = 0.0

    def apply(self, hand: int, rot: Q.Quat) -> Q.Quat:
        """The controller's rotation with its calibration and slider offsets, in its own axes."""
        with self.lock:
            self.raw[hand] = rot
            o = dict(self.offsets[hand])
            base = self.base[hand]
        q = Q.axis_angle((0.0, 1.0, 0.0), math.radians(o["yaw"]))
        q = Q.mul(q, Q.axis_angle((1.0, 0.0, 0.0), math.radians(o["pitch"])))
        q = Q.mul(q, Q.axis_angle((0.0, 0.0, 1.0), math.radians(o["roll"])))
        return Q.normalize(Q.mul(Q.mul(rot, base), q))

    def load(self) -> None:
        try:
            with open(SAVE) as fh:
                d = json.load(fh)
            for h in (0, 1):
                self.offsets[h] = dict(ZERO, **d["offsets"][h])
                self.base[h] = tuple(d["base"][h])
                self.calibrated[h] = bool(d["calibrated"][h])
            print(f"Tuner: loaded calibration from {SAVE}")
        except (OSError, ValueError, KeyError, IndexError, TypeError):
            pass

    def save(self) -> None:
        with self.lock:
            d = {"offsets": [self.offsets[0], self.offsets[1]], "base": [list(self.base[0]), list(self.base[1])],
                 "calibrated": [self.calibrated[0], self.calibrated[1]]}
        try:
            with open(SAVE, "w") as fh:
                json.dump(d, fh)
        except OSError:
            pass

    def offset_pos(self, hand: int, pos: Q.Vec) -> Q.Vec:
        """Height, forward and side nudges (cm) for this hand."""
        with self.lock:
            o = self.offsets[hand]
            return (pos[0] + o["side"] / 100.0, pos[1] + o["height"] / 100.0, pos[2] - o["forward"] / 100.0)

    def command(self) -> tuple[int, int]:
        with self.lock:
            return self.command_id, self.command_seq

    def calibrate_up(self, hand: int) -> None:
        """The controller is pointing straight up: its blade axis is whatever body axis points up now."""
        with self.lock:
            raw = self.raw.get(hand)
            if raw is None:
                return
            b = Q.rotate(Q.conj(raw), (0.0, 1.0, 0.0))
            self.base[hand] = _from_to((0.0, 0.0, -1.0), b)
            self.calibrated[hand] = True
            self.offsets[hand].update(yaw=0.0, pitch=0.0, roll=0.0)
        self.save()
        print(f"{'left' if hand == 0 else 'right'}: calibrated (blade axis in the controller: "
              f"{tuple(round(c, 2) for c in b)})")

    def record(self, hand: int, rot: Q.Quat, a_down: bool, gyro_ok: bool = True) -> None:
        now = time.monotonic()
        with self.lock:
            st = [t for t in self.stamps[hand] if now - t < 1.0] + [now]
            self.stamps[hand] = st
            self.latest[hand] = {"forward": Q.rotate(rot, (0.0, 0.0, -1.0)), "t": now, "rate": len(st), "a": a_down,
                                 "gyro": gyro_ok}

    def realign_bit(self) -> int:
        """Bit 2 of the phone packet's buttons while a realign request is fresh."""
        return 4 if time.monotonic() < self.realign_until else 0

    def state(self) -> dict:
        now = time.monotonic()
        with self.lock:
            hands = [None, None]
            for h, d in self.latest.items():
                hands[h] = {"forward": d["forward"], "age": now - d["t"], "rate": d["rate"], "a": d["a"],
                            "calibrated": self.calibrated[h], "gyro": d["gyro"]}
            scene = dict(self.scene, age=now - self.scene_t) if self.scene else None
            return {"hands": hands, "offsets": [self.offsets[0], self.offsets[1]], "scene": scene}

    # ---- the phone's game state, for the live view ----
    def _listen_spectator(self) -> None:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        sock.bind(("::", SPECTATOR_PORT))
        while True:
            data, _ = sock.recvfrom(65535)
            if len(data) < 4 + 4 * 9 + 16 * 19 or data[:4] != b"MPVS":
                continue
            f = struct.unpack(f"<{(len(data) - 4) // 4}f", data[4:4 + (len(data) - 4) // 4 * 4])
            head, S = f[:9], f[9:]
            v4 = lambda i: S[i * 4:i * 4 + 4]  # noqa: E731
            blades = []
            for h in range(2):
                a, b, c = v4(h), v4(2 + h), v4(4 + h)
                blades.append({"valid": a[3] > 0.5, "a": a[:3], "b": b[:3], "col": c[:3]})
            info = v4(6)
            boxes = []
            for i in range(int(info[0])):
                o = 19 + i * 5
                if (o + 5) * 4 > len(S):
                    break
                boxes.append({"c": v4(o)[:3], "ax": [v4(o + 1)[:3], v4(o + 2)[:3], v4(o + 3)[:3]], "col": v4(o + 4)[:3]})
            scene = {"head": {"pos": head[0:3], "fwd": head[3:6], "up": head[6:9]}, "blades": blades,
                     "boxes": boxes, "score": int(info[2]), "combo": int(info[3]),
                     "mode_id": int(round(v4(17)[3])), "scene_id": int(round(v4(18)[3]))}
            with self.lock:
                self.scene, self.scene_t = scene, time.monotonic()

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
                hand = data.get("hand")
                if self.path.startswith("/set") and hand in (0, 1):
                    with tuner.lock:
                        for k in ZERO:
                            if k in data:
                                tuner.offsets[hand][k] = float(data[k])
                    tuner.save()
                elif self.path.startswith("/calibrate") and hand in (0, 1):
                    tuner.calibrate_up(hand)
                elif self.path.startswith("/uncalibrate") and hand in (0, 1):
                    with tuner.lock:
                        tuner.base[hand], tuner.calibrated[hand] = Q.IDENTITY, False
                    tuner.save()
                elif self.path.startswith("/command") and data.get("cmd") in (1, 2, 10, 11, 12, 13, 14, 15, 20, 21, 30):
                    with tuner.lock:
                        tuner.command_id = int(data["cmd"])
                        tuner.command_seq = (tuner.command_seq + 1) % 256
                elif self.path.startswith("/realign"):
                    tuner.realign_until = time.monotonic() + 0.4
                self._send(b"{}", "application/json")

        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        threading.Thread(target=self._listen_spectator, daemon=True).start()
        print(f"Tuner page: http://localhost:{port}")
