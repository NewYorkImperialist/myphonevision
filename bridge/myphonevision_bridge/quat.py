"""Small quaternion helpers. Quaternions are (w, x, y, z) tuples.

SteamVR / VMT driver space: right-handed, +Y up, +X right, -Z forward.
"""

from __future__ import annotations

import math

Quat = tuple[float, float, float, float]
Vec = tuple[float, float, float]

IDENTITY: Quat = (1.0, 0.0, 0.0, 0.0)


def mul(a: Quat, b: Quat) -> Quat:
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (
        aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
    )


def conj(q: Quat) -> Quat:
    return (q[0], -q[1], -q[2], -q[3])


def normalize(q: Quat) -> Quat:
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return (q[0] / n, q[1] / n, q[2] / n, q[3] / n)


def axis_angle(axis: Vec, angle: float) -> Quat:
    s = math.sin(angle / 2)
    return (math.cos(angle / 2), axis[0] * s, axis[1] * s, axis[2] * s)


def rotate(q: Quat, v: Vec) -> Vec:
    p = mul(mul(q, (0.0, v[0], v[1], v[2])), conj(q))
    return (p[1], p[2], p[3])


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def from_matrix(m: list[list[float]]) -> Quat:
    """Rotation part of a 3x3 (or 3x4) row-major matrix to a quaternion."""
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = (0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s)
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = ((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s)
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = ((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s)
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = ((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s)
    return normalize(q)


def from_axes(x: Vec, y: Vec, z: Vec) -> Quat:
    """Rotation whose columns are the images of the unit X, Y, Z axes."""
    return from_matrix([[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]])


def yaw(q: Quat) -> float:
    """Heading about +Y of the device's forward (-Z) axis, in radians.

    When forward points nearly straight down or up its horizontal part is
    noise, so the heading comes from the device's up axis instead: pointing at
    the floor, the top of a held controller faces away from you; pointing at
    the ceiling, it faces you.
    """
    f = rotate(q, (0.0, 0.0, -1.0))
    if abs(f[1]) > 0.9:
        u = rotate(q, (0.0, 1.0, 0.0))
        d = u if f[1] < 0 else (-u[0], -u[1], -u[2])
        return math.atan2(-d[0], -d[2])
    return math.atan2(-f[0], -f[2])


def rot_y(angle: float) -> Quat:
    return axis_angle((0.0, 1.0, 0.0), angle)


def slerp(a: Quat, b: Quat, t: float) -> Quat:
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b = (-b[0], -b[1], -b[2], -b[3])
        dot = -dot
    if dot > 0.9995:
        return normalize(tuple(x + t * (y - x) for x, y in zip(a, b)))  # type: ignore[arg-type]
    theta = math.acos(dot)
    s = math.sin(theta)
    wa = math.sin((1 - t) * theta) / s
    wb = math.sin(t * theta) / s
    return tuple(wa * x + wb * y for x, y in zip(a, b))  # type: ignore[return-value]
