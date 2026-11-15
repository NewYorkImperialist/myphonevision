#!/usr/bin/env python3
"""Saber playground: a small SteamVR game of our own, for testing the headset and
controllers without anyone else's game in the way.

Each controller holds a glowing blade. Swing it through the floating cubes to
slice them; a slow touch only pushes them. Cross the two blades for sparks.
Every hit buzzes the controller. No buttons needed.

    python saber_playground.py                      # SteamVR (headset + bridge running)
    python saber_playground.py --desktop            # no headset: the mouse swings the right blade
                                                    #   (hold the left mouse button for the left one)
    python saber_playground.py --desktop --autoplay # both blades swing by themselves

Keys, on the laptop window: T toggles thrown cubes, R resets, C changes blade
colors, Esc quits. The window mirrors the left eye in VR mode, for the audience.
"""

from __future__ import annotations

import argparse
import ctypes
import math
import random
import sys
import time
import zlib

import numpy as np

import OpenGL

OpenGL.ERROR_CHECKING = False  # PyOpenGL's per-call checks cost too much per frame
import glfw  # noqa: E402
from OpenGL import GL as gl  # noqa: E402

BG = np.array([0.015, 0.015, 0.035], np.float32)
COLOR_SETS = [
    ((0.15, 0.55, 1.0), (1.0, 0.25, 0.08)),
    ((0.2, 1.0, 0.35), (0.75, 0.25, 1.0)),
    ((1.0, 0.75, 0.1), (0.1, 0.9, 1.0)),
]
SLICE_SPEED = 1.5      # m/s at the contact point; slower only pushes
HILT_BACK = 0.12    # hilt bottom, behind the controller origin (which sits in the grip)
HILT_LEN = 0.271
HILT_FRONT = HILT_LEN - HILT_BACK  # emitter mouth, ahead of the controller origin

# Hilt materials: rgb + a, where a > 0 is glow (emissive) and a < 0 is metal (shine).
CHROME = (0.82, 0.84, 0.88, -1.0)
STEEL = (0.5, 0.52, 0.56, -0.8)
GUNMETAL = (0.13, 0.13, 0.15, -0.5)
RUBBER = (0.035, 0.035, 0.04, 0.0)
RIB = (0.07, 0.07, 0.075, -0.25)
# Turned sections along the hilt: (mesh, from, to, radius, material), meters from the pommel.
HILT_PARTS = [
    ("cyl", 0.000, 0.006, 0.0165, GUNMETAL),   # pommel cap
    ("cyl", 0.006, 0.030, 0.0190, STEEL),      # pommel
    ("cyl", 0.030, 0.036, 0.0176, CHROME),
    ("cyl", 0.036, 0.135, 0.0158, RUBBER),     # grip
    *[("cyl", 0.040 + i * 0.0123, 0.0455 + i * 0.0123, 0.0177, RIB) for i in range(8)],  # grip ribs
    ("cyl", 0.135, 0.145, 0.0183, CHROME),
    ("cyl", 0.145, 0.200, 0.0168, STEEL),      # switch section
    ("cyl", 0.200, 0.207, 0.0183, CHROME),
    ("cyl", 0.207, 0.236, 0.0150, GUNMETAL),   # emitter neck
    ("flare", 0.236, 0.266, 0.0168, CHROME),   # emitter shroud, flares out 27%
    ("cyl", 0.266, 0.271, 0.0212, CHROME),     # emitter lip
]
IGNITE_S = 0.25
FLOAT_COUNT = 9
THROW_EVERY_S = 1.1


# ---- Math -------------------------------------------------------------------------

def normalize(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else v


def rot_axis(axis, ang):
    x, y, z = normalize(np.asarray(axis, np.float64))
    c, s, C = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def basis_from_y(y):
    """3x3 rotation whose +Y column is the unit vector y."""
    ref = np.array([0.0, 0.0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = normalize(np.cross(y, ref))
    z = np.cross(x, y)
    return np.column_stack((x, y, z))


def mat4(R=None, t=None):
    M = np.eye(4)
    if R is not None:
        M[:3, :3] = R
    if t is not None:
        M[:3, 3] = t
    return M


def perspective(fovy_deg, aspect, near, far):
    f = 1.0 / math.tan(math.radians(fovy_deg) / 2)
    return np.array([[f / aspect, 0, 0, 0], [0, f, 0, 0],
                     [0, 0, (far + near) / (near - far), 2 * far * near / (near - far)],
                     [0, 0, -1, 0]])


def seg_point(a, b, p):
    ab = b - a
    t = float(np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0.0, 1.0))
    return t, a + t * ab


def seg_seg(p1, q1, p2, q2):
    """Closest points between segments p1q1 and p2q2: (c1, c2)."""
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = np.dot(d1, d1), np.dot(d2, d2), np.dot(d2, r)
    c, b = np.dot(d1, r), np.dot(d1, d2)
    den = a * e - b * b
    s = float(np.clip((b * f - c * e) / den, 0, 1)) if den > 1e-12 else 0.0
    t = (b * s + f) / e if e > 1e-12 else 0.0
    if t < 0:
        t, s = 0.0, float(np.clip(-c / a, 0, 1)) if a > 1e-12 else 0.0
    elif t > 1:
        t, s = 1.0, float(np.clip((b - c) / a, 0, 1)) if a > 1e-12 else 0.0
    return p1 + d1 * s, p2 + d2 * t


def yaw_frame(head):
    """Head position and its horizontal forward direction."""
    pos = head[:3, 3].copy()
    f = -head[:3, 2]
    f = normalize(np.array([f[0], 0.0, f[2]])) if abs(f[0]) + abs(f[2]) > 1e-3 else np.array([0, 0, -1.0])
    return pos, f


# ---- GL helpers ---------------------------------------------------------------------

COMMON = """
uniform vec3 uBladeA[2];
uniform vec3 uBladeB[2];
uniform vec3 uBladeCol[2];
uniform vec3 uEye;
uniform vec3 uBg;
vec3 bladeLight(vec3 p, vec3 n) {
  vec3 sum = vec3(0.0);
  for (int i = 0; i < 2; i++) {
    vec3 ab = uBladeB[i] - uBladeA[i];
    float t = clamp(dot(p - uBladeA[i], ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    vec3 d = uBladeA[i] + t * ab - p;
    float ndl = max(dot(n, normalize(d)), 0.0) * 0.8 + 0.2;
    sum += uBladeCol[i] * ndl * 0.3 / (0.02 + dot(d, d) * 6.0);
  }
  return min(sum, vec3(2.0));
}
vec3 fogged(vec3 c, vec3 p) { return mix(c, uBg, 1.0 - exp(-length(uEye - p) * 0.07)); }
"""

VS_INST = """#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNrm;
layout(location=2) in float aSeg;
layout(location=3) in vec4 iM0;
layout(location=4) in vec4 iM1;
layout(location=5) in vec4 iM2;
layout(location=6) in vec4 iM3;
layout(location=7) in vec4 iScaleLen;
layout(location=8) in vec4 iColor;
uniform mat4 uVP;
out vec3 vN; out vec3 vW; out vec4 vC;
void main() {
  mat4 M = mat4(iM0, iM1, iM2, iM3);
  vec3 local = aPos * iScaleLen.xyz + vec3(0.0, aSeg * iScaleLen.w, 0.0);
  vec4 w = M * vec4(local, 1.0);
  vW = w.xyz; vN = mat3(M) * aNrm; vC = iColor;
  gl_Position = uVP * w;
}
"""

FS_LIT = """#version 330 core
in vec3 vN; in vec3 vW; in vec4 vC;
out vec4 frag;
""" + COMMON + """
void main() {
  vec3 n = normalize(vN);
  vec3 V = normalize(uEye - vW);
  float diff = max(dot(n, normalize(vec3(0.35, 1.0, 0.25))), 0.0) * 0.55 + 0.18;
  float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0) * 0.35;
  vec3 col;
  if (vC.a < 0.0) {  // metal: mirror-ish reflection of a dim room with a bright horizon, plus blade light
    float metal = -vC.a;
    vec3 r = reflect(-V, n);
    vec3 env = mix(vec3(0.03, 0.035, 0.06), vec3(0.06, 0.07, 0.11), step(0.0, r.y))
             + vec3(0.55, 0.6, 0.7) * exp(-abs(r.y) * 14.0) * 0.7
             + vec3(1.0) * pow(max(dot(r, normalize(vec3(0.35, 1.0, 0.25))), 0.0), 60.0) * 1.5;
    vec3 bl = min(bladeLight(vW, n), vec3(0.9));
    col = vC.rgb * (diff * (1.0 - metal * 0.7) + env * metal * 1.6 + bl * 0.8) + rim * vC.rgb * 0.5;
  } else {
    col = mix(vC.rgb * (diff + rim + bladeLight(vW, n)), vC.rgb * 1.6, vC.a);
  }
  frag = vec4(fogged(col, vW), 1.0);
}
"""

FS_GLOW = """#version 330 core
in vec3 vN; in vec3 vW; in vec4 vC;
out vec4 frag;
uniform vec3 uEye;
void main() {
  float f = pow(abs(dot(normalize(vN), normalize(uEye - vW))), 1.5);
  frag = vec4(vC.rgb * vC.a * f, 1.0);
}
"""

VS_FLOOR = """#version 330 core
layout(location=0) in vec3 aPos;
uniform mat4 uVP;
out vec3 vW;
void main() { vW = aPos; gl_Position = uVP * vec4(aPos, 1.0); }
"""

FS_FLOOR = """#version 330 core
in vec3 vW;
out vec4 frag;
uniform vec3 uCenter;
""" + COMMON + """
float grid(vec2 p, float step) {
  vec2 q = p / step;
  vec2 g = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec2(1e-4));
  return 1.0 - min(min(g.x, g.y), 1.0);
}
void main() {
  vec2 p = vW.xz;
  vec3 col = vec3(0.025, 0.03, 0.06)
           + vec3(0.10, 0.18, 0.35) * grid(p, 0.5) * 0.5
           + vec3(0.20, 0.35, 0.70) * grid(p, 2.0) * 0.6;
  float ring = 1.0 - smoothstep(0.0, 0.025, abs(length(p - uCenter.xz) - 1.2));
  col += vec3(0.3, 0.5, 1.0) * ring * 0.5;
  col += bladeLight(vW, vec3(0.0, 1.0, 0.0)) * 0.35;
  frag = vec4(fogged(col, vW), 1.0);
}
"""


def compile_program(vs, fs):
    def stage(src, kind):
        sh = gl.glCreateShader(kind)
        gl.glShaderSource(sh, src)
        gl.glCompileShader(sh)
        if not gl.glGetShaderiv(sh, gl.GL_COMPILE_STATUS):
            raise RuntimeError(gl.glGetShaderInfoLog(sh).decode())
        return sh
    prog = gl.glCreateProgram()
    gl.glAttachShader(prog, stage(vs, gl.GL_VERTEX_SHADER))
    gl.glAttachShader(prog, stage(fs, gl.GL_FRAGMENT_SHADER))
    gl.glLinkProgram(prog)
    if not gl.glGetProgramiv(prog, gl.GL_LINK_STATUS):
        raise RuntimeError(gl.glGetProgramInfoLog(prog).decode())
    names = ["uVP", "uEye", "uBg", "uBladeA", "uBladeB", "uBladeCol", "uCenter"]
    return prog, {n: gl.glGetUniformLocation(prog, n) for n in names}


def cube_mesh():
    verts, idx = [], []
    for axis in range(3):
        for sgn in (-1.0, 1.0):
            n = np.zeros(3)
            n[axis] = sgn
            u, v = np.eye(3)[(axis + 1) % 3], np.eye(3)[(axis + 2) % 3]
            base = len(verts)
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                verts.append([*(n + a * u + b * v), *n, 0.0])
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return np.array(verts, np.float32), np.array(idx, np.uint32)


def capsule_mesh(seg=16, rings=6):
    """Unit-radius capsule: bottom hemisphere at y=0 (seg 0), top at y=length (seg 1)."""
    lats = [(-math.pi / 2 + math.pi / 2 * i / rings, 0.0) for i in range(rings + 1)]
    lats += [(math.pi / 2 * i / rings, 1.0) for i in range(rings + 1)]
    verts = []
    for lat, s in lats:
        for j in range(seg + 1):
            lon = 2 * math.pi * j / seg
            n = [math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon)]
            verts.append([*n, *n, s])
    idx = []
    for r in range(len(lats) - 1):
        for j in range(seg):
            a, b = r * (seg + 1) + j, (r + 1) * (seg + 1) + j
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return np.array(verts, np.float32), np.array(idx, np.uint32)


def cylinder_mesh(seg=28, top_ratio=1.0):
    """Flat-capped cylinder (or flared, top radius x top_ratio): base at y=0, top at y=length."""
    verts, idx = [], []
    slope = (1.0 - top_ratio) * 0.6
    for j in range(seg + 1):
        a = 2 * math.pi * j / seg
        c, sn = math.cos(a), math.sin(a)
        n = normalize(np.array([c, slope, sn]))
        verts.append([c, 0, sn, *n, 0.0])
        verts.append([c * top_ratio, 0, sn * top_ratio, *n, 1.0])
    for j in range(seg):
        a = 2 * j
        idx += [a, a + 1, a + 2, a + 2, a + 1, a + 3]
    for s_, ny, r in ((0.0, -1.0, 1.0), (1.0, 1.0, top_ratio)):
        center = len(verts)
        verts.append([0, 0, 0, 0, ny, 0, s_])
        for j in range(seg + 1):
            a = 2 * math.pi * j / seg
            verts.append([math.cos(a) * r, 0, math.sin(a) * r, 0, ny, 0, s_])
        idx += [i for j in range(seg) for i in (center, center + 1 + j, center + 2 + j)]
    return np.array(verts, np.float32), np.array(idx, np.uint32)


class Batch:
    """One mesh drawn with per-instance pose, scale, length and color."""

    def __init__(self, mesh):
        verts, idx = mesh
        self.count = len(idx)
        self.vao = gl.glGenVertexArrays(1)
        gl.glBindVertexArray(self.vao)
        vbo, ebo, self.ibo = gl.glGenBuffers(3)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo)
        gl.glBufferData(gl.GL_ARRAY_BUFFER, verts.nbytes, verts, gl.GL_STATIC_DRAW)
        for loc, size, off in ((0, 3, 0), (1, 3, 12), (2, 1, 24)):
            gl.glEnableVertexAttribArray(loc)
            gl.glVertexAttribPointer(loc, size, gl.GL_FLOAT, False, 28, ctypes.c_void_p(off))
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo)
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, idx.nbytes, idx, gl.GL_STATIC_DRAW)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.ibo)
        for loc, size, off in ((3, 4, 0), (4, 4, 16), (5, 4, 32), (6, 4, 48), (7, 4, 64), (8, 4, 80)):
            gl.glEnableVertexAttribArray(loc)
            gl.glVertexAttribPointer(loc, size, gl.GL_FLOAT, False, 96, ctypes.c_void_p(off))
            gl.glVertexAttribDivisor(loc, 1)
        gl.glBindVertexArray(0)
        self.rows: list = []
        self.n = 0

    def add(self, M, scale, length, color):
        self.rows.append(np.concatenate((M.T.ravel(), scale, (length,), color)))

    def add_array(self, arr):
        self.rows.append(arr)

    def upload(self):
        parts = [r.reshape(-1, 24) for r in self.rows]
        data = np.ascontiguousarray(np.concatenate(parts), np.float32) if parts else np.zeros((0, 24), np.float32)
        self.rows, self.n = [], len(data)
        if self.n:
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.ibo)
            gl.glBufferData(gl.GL_ARRAY_BUFFER, data.nbytes, data, gl.GL_STREAM_DRAW)

    def draw(self):
        if self.n:
            gl.glBindVertexArray(self.vao)
            gl.glDrawElementsInstanced(gl.GL_TRIANGLES, self.count, gl.GL_UNSIGNED_INT, ctypes.c_void_p(0), self.n)


class EyeTarget:
    """Multisampled framebuffer resolved into a plain RGBA8 texture (what SteamVR takes)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        samples = min(4, int(gl.glGetIntegerv(gl.GL_MAX_SAMPLES)))
        self.msfbo = gl.glGenFramebuffers(1)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.msfbo)
        color, depth = gl.glGenRenderbuffers(2)
        gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, color)
        gl.glRenderbufferStorageMultisample(gl.GL_RENDERBUFFER, samples, gl.GL_RGBA8, w, h)
        gl.glFramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_RENDERBUFFER, color)
        gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, depth)
        gl.glRenderbufferStorageMultisample(gl.GL_RENDERBUFFER, samples, gl.GL_DEPTH_COMPONENT24, w, h)
        gl.glFramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_RENDERBUFFER, depth)
        self.tex = gl.glGenTextures(1)
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.tex)
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, w, h, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, None)
        for p in (gl.GL_TEXTURE_MIN_FILTER, gl.GL_TEXTURE_MAG_FILTER):
            gl.glTexParameteri(gl.GL_TEXTURE_2D, p, gl.GL_LINEAR)
        self.fbo = gl.glGenFramebuffers(1)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo)
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.tex, 0)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)

    def begin(self):
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.msfbo)
        gl.glViewport(0, 0, self.w, self.h)

    def resolve(self):
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, self.msfbo)
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.fbo)
        gl.glBlitFramebuffer(0, 0, self.w, self.h, 0, 0, self.w, self.h, gl.GL_COLOR_BUFFER_BIT, gl.GL_NEAREST)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)

    def to_window(self, win_w, win_h):
        """Blit into the window, cropped to fill it without stretching."""
        s = max(win_w / self.w, win_h / self.h)
        cw, ch = int(win_w / s), int(win_h / s)
        x0, y0 = (self.w - cw) // 2, (self.h - ch) // 2
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, self.fbo)
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, 0)
        gl.glBlitFramebuffer(x0, y0, x0 + cw, y0 + ch, 0, 0, win_w, win_h, gl.GL_COLOR_BUFFER_BIT, gl.GL_LINEAR)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)

    def save_png(self, path):
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, self.fbo)
        data = gl.glReadPixels(0, 0, self.w, self.h, gl.GL_RGB, gl.GL_UNSIGNED_BYTE)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
        rows = np.frombuffer(data, np.uint8).reshape(self.h, self.w * 3)[::-1]
        raw = b"".join(b"\x00" + r.tobytes() for r in rows)

        def chunk(t, d):
            return len(d).to_bytes(4, "big") + t + d + zlib.crc32(t + d).to_bytes(4, "big")
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", self.w.to_bytes(4, "big") + self.h.to_bytes(4, "big")
                                                + bytes([8, 2, 0, 0, 0]))
                    + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


# ---- Game ---------------------------------------------------------------------------

class Blade:
    def __init__(self, color):
        self.color = np.array(color)
        self.valid = False
        self.length = 0.0
        self.a = self.b = self.prev_a = self.prev_b = np.zeros(3)
        self.d = np.array([0, 1.0, 0])
        self.origin = np.zeros(3)
        self.R_ctrl = np.eye(3)
        self.trail: list = []
        self.haptic_frames = 0


class Target:
    def __init__(self, pos, home, vel, size, color, thrown):
        self.pos, self.home, self.vel = pos, home, vel
        self.size, self.color, self.thrown = size, np.array(color), thrown
        self.R = rot_axis(np.random.randn(3), random.uniform(0, 6.3))
        self.spin_axis, self.spin = normalize(np.random.randn(3)), random.uniform(0.3, 1.2)
        self.age, self.phase, self.cooldown = 0.0, random.uniform(0, 6.3), 0.0
        self.alive = True

    @property
    def radius(self):
        return self.size * 0.62


class Debris:
    def __init__(self, pos, vel, R, half, color):
        self.pos, self.vel, self.R, self.half, self.color = pos, vel, R, half, color
        self.spin_axis, self.spin = normalize(np.random.randn(3)), random.uniform(4, 10)
        self.life = 2.0


SEGMENTS = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
            "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": ""}


class Game:
    def __init__(self, blade_length, blade_pitch):
        self.blade_length = blade_length
        self.blade_dir_local = rot_axis((1, 0, 0), math.radians(blade_pitch)) @ np.array([0, 0, -1.0])
        self.color_set = 0
        self.blades = [Blade(c) for c in COLOR_SETS[0]]
        self.targets: list[Target] = []
        self.debris: list[Debris] = []
        self.spark_pos = np.zeros((0, 3))
        self.spark_vel = np.zeros((0, 3))
        self.spark_life = np.zeros(0)
        self.spark_col = np.zeros((0, 3))
        self.throw_mode = False
        self.throw_timer = 0.0
        self.spawn_timer = 0.0
        self.score = self.combo = 0
        self.last_slice = -10.0
        self.t = 0.0
        self.anchor = None   # (position, forward) of the head at start: scoreboard and pillars
        self.head = mat4(t=(0, 1.6, 0))
        self.clash_cooldown = 0.0

    # -- input --
    def reset(self):
        self.targets.clear()
        self.debris.clear()
        self.score = self.combo = 0
        self.anchor = None

    def cycle_colors(self):
        self.color_set = (self.color_set + 1) % len(COLOR_SETS)
        for b, c in zip(self.blades, COLOR_SETS[self.color_set]):
            b.color = np.array(c)

    # -- helpers --
    def sparks(self, at, base_vel, n, color, spread=2.5):
        dirs = np.random.randn(n, 3)
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
        vel = base_vel + dirs * np.random.uniform(0.3, 1.0, (n, 1)) * spread
        col = np.clip(np.array(color) * 0.6 + 0.5, 0, 1)
        self.spark_pos = np.vstack((self.spark_pos, np.tile(at, (n, 1))))[-1500:]
        self.spark_vel = np.vstack((self.spark_vel, vel))[-1500:]
        self.spark_life = np.concatenate((self.spark_life, np.random.uniform(0.25, 0.7, n)))[-1500:]
        self.spark_col = np.vstack((self.spark_col, np.tile(col, (n, 1))))[-1500:]

    def spawn_float(self):
        pos, f = yaw_frame(self.head)
        ang = random.uniform(-1.9, 1.9)
        d = rot_axis((0, 1, 0), ang) @ f
        home = pos + d * random.uniform(0.75, 1.35)
        home[1] = random.uniform(0.85, 1.75)
        hue = random.random()
        color = np.clip(np.abs(np.array([hue * 6 - 3, 2 - abs(hue * 6 - 2), 2 - abs(hue * 6 - 4)])) - [1, 0, 0], 0.15, 1)
        self.targets.append(Target(home.copy(), home, np.zeros(3), random.uniform(0.17, 0.25), color, False))

    def spawn_thrown(self):
        apos, af = self.anchor
        hpos, _ = yaw_frame(self.head)
        right = np.cross(af, (0, 1, 0))
        start = apos + af * 4.5 + right * random.uniform(-0.6, 0.6)
        start[1] = random.uniform(1.0, 1.6)
        aim = hpos + af * 0.45 + right * random.uniform(-0.35, 0.35)
        aim[1] = random.uniform(1.0, 1.5)
        vel = normalize(aim - start) * 3.0
        self.targets.append(Target(start, start, vel, 0.2, (1.0, 0.85, 0.2), True))

    # -- simulation --
    def update(self, dt, head, hands):
        self.t += dt
        self.head = head
        if self.anchor is None:
            self.anchor = yaw_frame(head)
        for blade, M in zip(self.blades, hands):
            self.update_blade(blade, M, dt)
        self.collide(dt)
        self.update_targets(dt)
        self.update_debris(dt)
        self.update_sparks(dt)

    def update_blade(self, b, M, dt):
        if M is None:
            b.valid, b.length = False, 0.0
            b.trail.clear()
            return
        d = normalize(M[:3, :3] @ self.blade_dir_local)
        b.origin, b.d, b.R_ctrl = M[:3, 3].copy(), d, M[:3, :3].copy()
        b.length = min(self.blade_length, b.length + self.blade_length * dt / IGNITE_S)
        a = b.origin + d * HILT_FRONT
        if not b.valid:
            b.prev_a, b.prev_b = a, a + d * b.length
        else:
            b.prev_a, b.prev_b = b.a, b.b
        b.a, b.b, b.valid = a, a + d * b.length, True
        b.trail = ([(b.prev_a, b.prev_b)] + b.trail)[:5]

    def collide(self, dt):
        for hand, b in enumerate(self.blades):
            if not b.valid or b.length < 0.2:
                continue
            for tg in self.targets:
                if not tg.alive or tg.cooldown > 0:
                    continue
                for u in (0.25, 0.5, 0.75, 1.0):
                    A = b.prev_a + (b.a - b.prev_a) * u
                    B = b.prev_b + (b.b - b.prev_b) * u
                    s, c = seg_point(A, B, tg.pos)
                    if np.linalg.norm(c - tg.pos) < tg.radius + 0.02:
                        p_now = b.a + (b.b - b.a) * s
                        p_prev = b.prev_a + (b.prev_b - b.prev_a) * s
                        v = (p_now - p_prev) / max(dt, 1e-3)
                        if np.linalg.norm(v) > SLICE_SPEED:
                            self.slice(tg, b, c, v, hand)
                        else:
                            tg.vel = tg.vel + normalize(tg.pos - c) * (np.linalg.norm(v) * 0.8 + 0.4) + v * 0.4
                            tg.cooldown = 0.15
                            b.haptic_frames = max(b.haptic_frames, 1)
                            self.sparks(c, np.zeros(3), 4, b.color, 0.8)
                        break
        b0, b1 = self.blades
        self.clash_cooldown -= dt
        if b0.valid and b1.valid and b0.length > 0.2 and b1.length > 0.2 and self.clash_cooldown <= 0:
            c0, c1 = seg_seg(b0.a, b0.b, b1.a, b1.b)
            if np.linalg.norm(c0 - c1) < 0.04:
                mid = (c0 + c1) / 2
                self.sparks(mid, np.zeros(3), 30, (1, 1, 1), 3.0)
                b0.haptic_frames = b1.haptic_frames = 3
                self.clash_cooldown = 0.08

    def slice(self, tg, b, c, v, hand):
        tg.alive = False
        n = np.cross(b.d, v)
        n = normalize(n) if np.linalg.norm(n) > 1e-6 else basis_from_y(b.d)[:, 0]
        k = int(np.argmax(np.abs(tg.R.T @ n)))
        half = np.full(3, tg.size / 2)
        half[k] /= 2
        for sgn in (1, -1):
            axis = tg.R[:, k] * sgn
            vel = tg.vel + v * 0.25 + axis * random.uniform(1.0, 1.8) + np.random.randn(3) * 0.2
            self.debris.append(Debris(tg.pos + axis * tg.size / 4, vel, tg.R.copy(), half.copy(), tg.color))
        self.sparks(c, v * 0.3, 26, b.color)
        b.haptic_frames = 5
        self.combo = self.combo + 1 if self.t - self.last_slice < 2.0 else 1
        self.last_slice = self.t
        self.score += self.combo

    def update_targets(self, dt):
        hpos, _ = yaw_frame(self.head)
        for tg in self.targets:
            tg.age += dt
            tg.cooldown -= dt
            tg.R = rot_axis(tg.spin_axis, tg.spin * dt) @ tg.R
            if tg.thrown:
                tg.vel[1] -= 0.8 * dt
                tg.pos = tg.pos + tg.vel * dt
                if np.dot(tg.pos - hpos, normalize(tg.vel)) > 0.7 or tg.age > 6:
                    tg.alive = False
                    self.combo = 0
            else:
                home = tg.home + np.array([0, 0.03 * math.sin(tg.age * 1.3 + tg.phase), 0])
                tg.vel = tg.vel + (4.0 * (home - tg.pos) - 2.5 * tg.vel) * dt
                tg.pos = tg.pos + tg.vel * dt
                if tg.pos[1] < 0.1 or np.linalg.norm(tg.pos - hpos) > 8:
                    tg.alive = False
        self.targets = [t for t in self.targets if t.alive]
        floating = sum(1 for t in self.targets if not t.thrown)
        self.spawn_timer -= dt
        if floating < FLOAT_COUNT and self.spawn_timer <= 0:
            self.spawn_float()
            self.spawn_timer = 0.35
        if self.throw_mode:
            self.throw_timer -= dt
            if self.throw_timer <= 0:
                self.spawn_thrown()
                self.throw_timer = THROW_EVERY_S

    def update_debris(self, dt):
        for d in self.debris:
            d.vel[1] -= 9.8 * dt
            d.pos = d.pos + d.vel * dt
            d.R = rot_axis(d.spin_axis, d.spin * dt) @ d.R
            low = float(np.max(np.abs(d.R) @ d.half))
            if d.pos[1] < low:
                d.pos[1] = low
                d.vel = d.vel * np.array([0.6, -0.3, 0.6])
                d.spin *= 0.7
            d.life -= dt
        self.debris = [d for d in self.debris if d.life > 0]

    def update_sparks(self, dt):
        if not len(self.spark_life):
            return
        self.spark_vel[:, 1] -= 9.8 * dt
        self.spark_vel *= 1 - 1.5 * dt
        self.spark_pos += self.spark_vel * dt
        low = self.spark_pos[:, 1] < 0
        self.spark_pos[low, 1] = 0
        self.spark_vel[low, 1] *= -0.4
        self.spark_life -= dt
        keep = self.spark_life > 0
        self.spark_pos, self.spark_vel = self.spark_pos[keep], self.spark_vel[keep]
        self.spark_life, self.spark_col = self.spark_life[keep], self.spark_col[keep]

    # -- drawing --
    def build(self, r):
        solid_cubes, solid_caps, glow_caps = r.cubes, r.caps, r.glows
        for tg in self.targets:
            s = min(1.0, tg.age / 0.3) * tg.size / 2
            solid_cubes.add(mat4(tg.R, tg.pos), np.full(3, s), 0.0, (*tg.color, 0.12))
        for d in self.debris:
            shrink = min(1.0, d.life / 0.4)
            solid_cubes.add(mat4(d.R, d.pos), d.half * shrink, 0.0, (*d.color, 0.12))
        for b in self.blades:
            if not b.valid:
                continue
            R = basis_from_y(b.d)
            self.build_hilt(r, b)
            core = np.clip(b.color * 0.35 + 0.65, 0, 1)
            M = mat4(R, b.a)
            solid_caps.add(M, np.full(3, 0.011), b.length, (*core, 1.0))
            for rad, k in ((0.022, 0.5), (0.04, 0.22), (0.075, 0.09)):
                glow_caps.add(mat4(R, b.a + b.d * rad), np.full(3, rad), max(0.0, b.length - rad), (*b.color, k))
            for i, (ta, tb) in enumerate(b.trail[1:]):
                seg = tb - ta
                L = float(np.linalg.norm(seg))
                if L > 0.05:
                    glow_caps.add(mat4(basis_from_y(seg / L), ta), np.full(3, 0.03), L, (*b.color, 0.06 / (i + 1)))
        n = len(self.spark_life)
        if n:
            speed = np.linalg.norm(self.spark_vel, axis=1, keepdims=True)
            y = self.spark_vel / np.maximum(speed, 1e-6)
            ref = np.where(np.abs(y[:, 2:3]) < 0.9, [[0, 0, 1.0]], [[1.0, 0, 0]])
            x = np.cross(y, ref)
            x /= np.maximum(np.linalg.norm(x, axis=1, keepdims=True), 1e-9)
            z = np.cross(x, y)
            rows = np.zeros((n, 24))
            rows[:, 0:3], rows[:, 4:7], rows[:, 8:11] = x, y, z
            rows[:, 12:15], rows[:, 15] = self.spark_pos - y * speed * 0.012, 1.0
            rows[:, 16:19] = 0.006
            rows[:, 19] = speed[:, 0] * 0.012 + 0.005
            rows[:, 20:23] = self.spark_col
            rows[:, 23] = np.clip(self.spark_life * 2.5, 0, 1)
            glow_caps.add_array(rows)
        self.build_world(solid_cubes)

    @staticmethod
    def build_hilt(r, b):
        # Hilt frame: y along the blade, z toward the controller's top (thumb side), so the
        # switch plate and button roll with the hand.
        d = b.d
        cx = b.R_ctrl[:, 0]
        x = cx - np.dot(cx, d) * d
        x = normalize(x) if np.linalg.norm(x) > 1e-3 else basis_from_y(d)[:, 0]
        z = np.cross(x, d)
        R = np.column_stack((x, d, z))
        base = b.origin - d * HILT_BACK
        for mesh, y0, y1, rad, mat in HILT_PARTS:
            (r.flares if mesh == "flare" else r.cyls).add(mat4(R, base + d * y0), np.full(3, rad), y1 - y0, mat)
        # Switch plate, activation button and a small status light on the thumb side.
        r.cubes.add(mat4(R, base + d * 0.1725 + z * 0.0172), (0.0055, 0.0165, 0.0032), 0.0, GUNMETAL)
        R_btn = np.column_stack((x, z, -d))
        r.cyls.add(mat4(R_btn, base + d * 0.180 + z * 0.0200), np.full(3, 0.0034), 0.0028, (0.9, 0.08, 0.05, 0.35))
        r.cubes.add(mat4(R, base + d * 0.160 + z * 0.0205), (0.0022, 0.0022, 0.0008), 0.0, (*b.color, 1.0))
        # Small vents around the emitter neck.
        for k in range(6):
            a = 2 * math.pi * k / 6
            rad_dir = x * math.cos(a) + z * math.sin(a)
            Rv = np.column_stack((np.cross(d, rad_dir), d, rad_dir))
            r.cubes.add(mat4(Rv, base + d * 0.2215 + rad_dir * 0.0148), (0.0022, 0.009, 0.0012), 0.0, (0.01, 0.01, 0.012, 0.0))

    def build_world(self, cubes):
        if self.anchor is None:
            return
        apos, f = self.anchor
        right = np.cross(f, (0, 1, 0))
        Rb = np.column_stack((right, (0, 1, 0), -f))
        for i in range(16):
            ang = 2 * math.pi * i / 16
            p = apos + (rot_axis((0, 1, 0), ang) @ f) * 7.0
            h = 3.0 + 2.5 * ((i * 7) % 5) / 4
            R = rot_axis((0, 1, 0), ang)
            cubes.add(mat4(R, (p[0], h / 2, p[2])), (0.25, h / 2, 0.25), 0.0, (0.12, 0.16, 0.3, 0.0))
            cubes.add(mat4(R, (p[0], h + 0.04, p[2])), (0.27, 0.04, 0.27), 0.0, (*COLOR_SETS[self.color_set][i % 2], 0.9))
        board = apos + f * 2.8
        board[1] = 2.2
        self.digits(cubes, board, Rb, f"{self.score:4d}"[-4:], 0.30)
        if self.combo >= 2:
            self.digits(cubes, board - np.array([0, 0.33, 0]), Rb, f"x{self.combo}"[-3:].replace("x", " "), 0.16)

    @staticmethod
    def digits(cubes, center, R, text, h):
        w, t = h * 0.55, h * 0.11
        segs = {"a": (0, h / 2, 1), "b": (w / 2, h / 4, 0), "c": (w / 2, -h / 4, 0), "d": (0, -h / 2, 1),
                "e": (-w / 2, -h / 4, 0), "f": (-w / 2, h / 4, 0), "g": (0, 0, 1)}
        pitch = w * 1.6
        x0 = -pitch * (len(text) - 1) / 2
        for i, ch in enumerate(text):
            on = SEGMENTS.get(ch, "")
            for name, (sx, sy, horiz) in segs.items():
                half = (w / 2, t / 2, t / 2) if horiz else (t / 2, h / 4, t / 2)
                p = center + R @ np.array([x0 + i * pitch + sx, sy, 0])
                color = (0.6, 0.9, 1.0, 1.0) if name in on else (0.05, 0.07, 0.12, 0.6)
                cubes.add(mat4(R, p), half, 0.0, color)

    def blade_uniforms(self):
        A = np.zeros((2, 3), np.float32)
        B = np.zeros((2, 3), np.float32)
        C = np.zeros((2, 3), np.float32)
        for i, b in enumerate(self.blades):
            if b.valid:
                A[i], B[i], C[i] = b.a, b.b, b.color * min(1.0, b.length / self.blade_length)
        return A, B, C


# ---- Rendering ----------------------------------------------------------------------

class Renderer:
    def __init__(self):
        self.lit = compile_program(VS_INST, FS_LIT)
        self.glow = compile_program(VS_INST, FS_GLOW)
        self.floor = compile_program(VS_FLOOR, FS_FLOOR)
        self.cubes, self.caps, self.glows = Batch(cube_mesh()), Batch(capsule_mesh()), Batch(capsule_mesh())
        self.cyls, self.flares = Batch(cylinder_mesh()), Batch(cylinder_mesh(top_ratio=1.27))
        quad = np.array([[-40, 0, -40], [40, 0, -40], [40, 0, 40], [-40, 0, -40], [40, 0, 40], [-40, 0, 40]], np.float32)
        self.floor_vao = gl.glGenVertexArrays(1)
        gl.glBindVertexArray(self.floor_vao)
        vbo = gl.glGenBuffers(1)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo)
        gl.glBufferData(gl.GL_ARRAY_BUFFER, quad.nbytes, quad, gl.GL_STATIC_DRAW)
        gl.glEnableVertexAttribArray(0)
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, False, 12, ctypes.c_void_p(0))
        gl.glBindVertexArray(0)

    def prepare(self, game):
        game.build(self)
        for b in (self.cubes, self.caps, self.glows, self.cyls, self.flares):
            b.upload()
        self.blades = game.blade_uniforms()
        self.center = game.anchor[0] if game.anchor else np.zeros(3)

    def _uniforms(self, prog, VP, eye):
        p, u = prog
        gl.glUseProgram(p)
        gl.glUniformMatrix4fv(u["uVP"], 1, gl.GL_TRUE, VP.astype(np.float32))
        gl.glUniform3fv(u["uEye"], 1, eye.astype(np.float32))
        if u["uBg"] >= 0:
            gl.glUniform3fv(u["uBg"], 1, BG)
            A, B, C = self.blades
            gl.glUniform3fv(u["uBladeA"], 2, A)
            gl.glUniform3fv(u["uBladeB"], 2, B)
            gl.glUniform3fv(u["uBladeCol"], 2, C)
        if u["uCenter"] >= 0:
            gl.glUniform3fv(u["uCenter"], 1, np.asarray(self.center, np.float32))

    def draw(self, VP, eye):
        gl.glClearColor(*BG, 1.0)
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)
        gl.glEnable(gl.GL_DEPTH_TEST)
        gl.glDepthMask(gl.GL_TRUE)
        gl.glDisable(gl.GL_BLEND)
        gl.glDisable(gl.GL_CULL_FACE)
        self._uniforms(self.floor, VP, eye)
        gl.glBindVertexArray(self.floor_vao)
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6)
        self._uniforms(self.lit, VP, eye)
        self.cubes.draw()
        self.caps.draw()
        self.cyls.draw()
        self.flares.draw()
        self._uniforms(self.glow, VP, eye)
        gl.glDepthMask(gl.GL_FALSE)
        gl.glEnable(gl.GL_BLEND)
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE)
        self.glows.draw()
        gl.glDepthMask(gl.GL_TRUE)
        gl.glDisable(gl.GL_BLEND)
        gl.glBindVertexArray(0)


# ---- Hands outside VR -------------------------------------------------------------

def hand_matrix(origin, blade_dir, blade_dir_local):
    """Controller pose whose blade (blade_dir_local in controller axes) points along blade_dir."""
    R_world = basis_from_y(normalize(blade_dir))
    R_local = basis_from_y(normalize(blade_dir_local))
    return mat4(R_world @ R_local.T, origin)


def autoplay_hands(t, head, local_dir):
    pos, f = yaw_frame(head)
    right = np.cross(f, (0, 1, 0))
    hands = []
    for side, phase in ((-1, 0.0), (1, 1.7)):
        a = t * 2.4 + phase
        origin = pos + f * 0.35 + right * (0.22 * side + 0.12 * math.sin(a * 0.5)) + np.array([0, -0.45, 0])
        d = right * math.sin(a) * 1.1 * -side + np.array([0, 1, 0]) * (0.35 + 0.8 * math.cos(a)) + f * 0.9
        hands.append(hand_matrix(origin, d, local_dir))
    return hands


class MouseHands:
    def __init__(self):
        self.prev = None
        self.vel = np.zeros(2)

    def hands(self, win, head, dt, t, local_dir):
        w, h = glfw.get_window_size(win)
        mx, my = glfw.get_cursor_pos(win)
        m = np.array([mx / max(w, 1) * 2 - 1, 1 - my / max(h, 1) * 2])
        if self.prev is not None and dt > 0:
            self.vel = self.vel * 0.7 + (m - self.prev) / dt * 0.3
        self.prev = m
        pos, f = yaw_frame(head)
        right = np.cross(f, (0, 1, 0))
        origin = pos + f * 0.45 + right * (m[0] * 0.55) + np.array([0, -0.4 + m[1] * 0.45, 0])
        lean = np.clip(self.vel * 0.35, -2.5, 2.5)
        d = np.array([0, 1.0, 0]) * 0.8 + f * 0.6 + right * lean[0] + np.array([0, lean[1] * 0.5, 0])
        driven = hand_matrix(origin, d, local_dir)
        swap = glfw.get_mouse_button(win, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS
        side = 1 if swap else -1  # the idle hand rests on the other side
        idle = pos + f * 0.35 + right * 0.3 * side + np.array([0, -0.5, 0])
        idle_hand = hand_matrix(idle, np.array([0, 1.0, 0]) + f * 0.5 + right * 0.15 * math.sin(t), local_dir)
        return [driven, idle_hand] if swap else [idle_hand, driven]


# ---- Main loops ---------------------------------------------------------------------

def make_window(w, h, visible, title):
    # SteamVR's OpenGL texture sharing on Linux expects a GLX context: use X11
    # (XWayland on a Wayland desktop) rather than an EGL/Wayland one.
    if sys.platform.startswith("linux") and hasattr(glfw, "PLATFORM_X11"):
        glfw.init_hint(glfw.PLATFORM, glfw.PLATFORM_X11)
    if not glfw.init():
        sys.exit("glfw init failed")
    glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.window_hint(glfw.OPENGL_FORWARD_COMPAT, True)
    glfw.window_hint(glfw.VISIBLE, visible)
    win = glfw.create_window(w, h, title, None, None)
    if not win:
        sys.exit("could not open an OpenGL 3.3 window")
    glfw.make_context_current(win)
    glfw.swap_interval(0)
    return win


def key_handler(game, quit_flag):
    def on_key(win, key, scancode, action, mods):
        if action != glfw.PRESS:
            return
        if key == glfw.KEY_ESCAPE:
            quit_flag[0] = True
        elif key == glfw.KEY_T:
            game.throw_mode = not game.throw_mode
            print("thrown cubes", "on" if game.throw_mode else "off")
        elif key == glfw.KEY_R:
            game.reset()
        elif key == glfw.KEY_C:
            game.cycle_colors()
    return on_key


def run_desktop(args, game):
    win = make_window(1280, 720, not args.screenshot, "Saber playground (desktop)")
    fw, fh = glfw.get_framebuffer_size(win)
    target = EyeTarget(fw, fh)
    renderer = Renderer()
    quit_flag = [False]
    glfw.set_key_callback(win, key_handler(game, quit_flag))
    mouse = MouseHands()
    head = mat4(t=(0, 1.6, 0))
    P = perspective(70, fw / fh, 0.05, 60)
    prev, frame = time.perf_counter(), 0
    while not glfw.window_should_close(win) and not quit_flag[0]:
        glfw.poll_events()
        now = time.perf_counter()
        dt = 1 / 60 if args.screenshot else min(now - prev, 0.05)
        prev = now
        t = game.t + dt
        hands = autoplay_hands(t, head, game.blade_dir_local) if args.autoplay else \
            mouse.hands(win, head, dt, t, game.blade_dir_local)
        game.update(dt, head, hands)
        renderer.prepare(game)
        target.begin()
        renderer.draw(P @ np.linalg.inv(head), head[:3, 3])
        target.resolve()
        frame += 1
        if args.screenshot and frame >= args.frames:
            target.save_png(args.screenshot)
            print("saved", args.screenshot, "score", game.score)
            break
        target.to_window(fw, fh)
        glfw.swap_buffers(win)
    glfw.terminate()


def run_vr(args, game):
    try:
        import openvr
    except Exception as e:  # noqa: BLE001
        sys.exit(f"pyopenvr isn't available ({e}); pip install openvr, or use --desktop")
    vrsys = openvr.init(openvr.VRApplication_Scene)
    comp = openvr.VRCompositor()
    w, h = vrsys.getRecommendedRenderTargetSize()
    print(f"SteamVR: {w} x {h} per eye")
    win = make_window(960, 540, True, "Saber playground (mirror: left eye)")
    eyes = [EyeTarget(w, h), EyeTarget(w, h)]
    renderer = Renderer()
    quit_flag = [False]
    glfw.set_key_callback(win, key_handler(game, quit_flag))

    def m34(m):
        M = np.eye(4)
        M[:3, :4] = np.ctypeslib.as_array(m.m)
        return M

    eye_ids = (openvr.Eye_Left, openvr.Eye_Right)
    proj = [np.ctypeslib.as_array(vrsys.getProjectionMatrix(e, 0.05, 60.0).m).astype(np.float64) for e in eye_ids]
    eye_to_head = [m34(vrsys.getEyeToHeadTransform(e)) for e in eye_ids]
    poses = (openvr.TrackedDevicePose_t * openvr.k_unMaxTrackedDeviceCount)()
    event = openvr.VREvent_t()
    devices: list = [None, None]
    next_scan, prev = 0.0, time.perf_counter()
    head = mat4(t=(0, 1.6, 0))
    frames, fps_t = 0, time.perf_counter()
    try:
        while not glfw.window_should_close(win) and not quit_flag[0]:
            glfw.poll_events()
            while vrsys.pollNextEvent(event):
                if event.eventType == openvr.VREvent_Quit:
                    quit_flag[0] = True
            now = time.perf_counter()
            if now >= next_scan:
                devices = scan_controllers(openvr, vrsys, devices)
                next_scan = now + 1.0
            comp.waitGetPoses(poses, None)
            if poses[openvr.k_unTrackedDeviceIndex_Hmd].bPoseIsValid:
                head = m34(poses[openvr.k_unTrackedDeviceIndex_Hmd].mDeviceToAbsoluteTracking)
            hands = []
            for dev in devices:
                ok = dev is not None and poses[dev].bPoseIsValid and poses[dev].bDeviceIsConnected
                hands.append(m34(poses[dev].mDeviceToAbsoluteTracking) if ok else None)
            now = time.perf_counter()
            dt, prev = min(now - prev, 0.05), now
            game.update(dt, head, hands)
            renderer.prepare(game)
            for i, target in enumerate(eyes):
                eye_pose = head @ eye_to_head[i]
                target.begin()
                renderer.draw(proj[i] @ np.linalg.inv(eye_pose), eye_pose[:3, 3])
                target.resolve()
                tex = openvr.Texture_t()
                tex.handle = int(target.tex)
                tex.eType = openvr.TextureType_OpenGL
                tex.eColorSpace = openvr.ColorSpace_Gamma
                try:
                    comp.submit(eye_ids[i], tex)
                except openvr.error_code.CompositorError as e:
                    print("submit failed:", e)
            gl.glFlush()
            for b, dev in zip(game.blades, devices):
                if b.haptic_frames > 0 and dev is not None:
                    vrsys.triggerHapticPulse(dev, 0, 3999)
                b.haptic_frames = max(0, b.haptic_frames - 1)
            fw, fh = glfw.get_framebuffer_size(win)
            eyes[0].to_window(fw, fh)
            glfw.swap_buffers(win)
            frames += 1
            if now - fps_t > 5:
                print(f"{frames / (now - fps_t):.0f} fps, score {game.score}, "
                      f"hands {'L' if hands[0] is not None else '-'}{'R' if hands[1] is not None else '-'}")
                frames, fps_t = 0, now
    finally:
        openvr.shutdown()
        glfw.terminate()


def scan_controllers(openvr, vrsys, current):
    """Device index per hand (left, right), preferring VMT's controllers."""
    best: list = [None, None]
    rank = [-1, -1]
    for i in range(1, openvr.k_unMaxTrackedDeviceCount):
        if vrsys.getTrackedDeviceClass(i) != openvr.TrackedDeviceClass_Controller:
            continue
        role = vrsys.getControllerRoleForTrackedDeviceIndex(i)
        hand = 0 if role == openvr.TrackedControllerRole_LeftHand else 1 if role == openvr.TrackedControllerRole_RightHand else None
        if hand is None:
            continue
        try:
            name = vrsys.getStringTrackedDeviceProperty(i, openvr.Prop_TrackingSystemName_String).lower()
        except Exception:  # noqa: BLE001
            name = ""
        r = 1 if ("vmt" in name or "virtual" in name) else 0
        if r > rank[hand]:
            best[hand], rank[hand] = i, r
    if best != current:
        print("controllers: left", best[0], "right", best[1])
    return best


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--desktop", action="store_true", help="no headset: draw in a window, mouse swings the right blade")
    ap.add_argument("--autoplay", action="store_true", help="with --desktop: both blades swing by themselves")
    ap.add_argument("--blade-length", type=float, default=1.0, metavar="M")
    ap.add_argument("--blade-pitch", type=float, default=0.0, metavar="DEG",
                    help="tilt the blades up (+) or down (-) if they don't line up with the controllers")
    ap.add_argument("--throw", action="store_true", help="start with cubes thrown at you (T toggles)")
    ap.add_argument("--screenshot", metavar="PNG", help="with --desktop: render offscreen, save a frame, exit")
    ap.add_argument("--frames", type=int, default=240, help="frames to run before --screenshot")
    ap.add_argument("--seed", type=int)
    args = ap.parse_args()
    if args.seed is not None:
        random.seed(args.seed)
        np.random.seed(args.seed)
    game = Game(args.blade_length, args.blade_pitch)
    game.throw_mode = args.throw
    (run_desktop if args.desktop else run_vr)(args, game)


if __name__ == "__main__":
    main()
