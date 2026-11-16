"""Controller orientation and arm-model position (position rung 1).

Orientation chain, in SteamVR driver space:
    R_device = yaw_offset * IMU_TO_VR * R_imu * MOUNT
R_imu is the controller's fused IMU orientation (sensor -> IMU world, Z up).
MOUNT maps the controller's SteamVR body axes into sensor axes, so it depends
on how the GY-521 sits in the printed handle.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from . import quat as Q

# IMU world (Z up) -> SteamVR (Y up): rotate -90 degrees about X.
IMU_TO_VR = Q.axis_angle((1.0, 0.0, 0.0), -math.pi / 2)

# Named mountings: for each SteamVR body axis (X right, Y up, Z back), the
# sensor axis it points along. Add one if your handle holds the board
# differently; print a still controller with --debug to check.
MOUNTS = {
    # Board flat, component side up, sensor +X pointing out of the controller's tip.
    "flat-x-forward": Q.from_axes((0, -1, 0), (0, 0, 1), (-1, 0, 0)),
    # Board flat, component side up, sensor +Y pointing out of the tip.
    "flat-y-forward": Q.from_axes((1, 0, 0), (0, 0, 1), (0, -1, 0)),
    # Board standing in the handle, sensor +Z out of the tip, +Y up.
    "upright-z-forward": Q.from_axes((-1, 0, 0), (0, 1, 0), (0, 0, -1)),
}


@dataclass
class ArmModel:
    """Fixed shoulder under the head; the upper arm swings most of the way from
    hanging down toward where the controller points; forearm along the controller."""

    shoulder: tuple[float, float, float] = (0.19, -0.23, 0.08)  # right side; X mirrored for left
    upper_arm: float = 0.28
    forearm: float = 0.27
    elbow_follow: float = 0.85  # 0 = upper arm hangs straight down, 1 = straight arm along the controller
    grip_offset: float = 0.05  # wrist to grip center along the controller's forward axis

    def position(self, hand: int, hmd_pos: Q.Vec, hmd_rot: Q.Quat, ctrl_rot: Q.Quat) -> Q.Vec:
        # Heading from the head's right axis: Q.yaw switches method past ~64 deg of head pitch,
        # which threw the shoulders (and hands) ~36 cm when looking down.
        r = Q.rotate(hmd_rot, (1.0, 0.0, 0.0))
        body = Q.rot_y(math.atan2(-r[2], r[0]))
        side = -1.0 if hand == 0 else 1.0
        sx, sy, sz = self.shoulder
        shoulder = Q.add(hmd_pos, Q.rotate(body, (side * sx, sy, sz)))
        # Upper arm along a blend of straight down and where the controller points (not its twist:
        # slerping the full rotation flipped at 180 deg and threw the elbow ~53 cm). With follow > 0.5
        # the blend never cancels, so there's no direction where the elbow has to pick a side.
        fwd = Q.rotate(ctrl_rot, (0.0, 0.0, -1.0))
        f = self.elbow_follow
        d = (f * fwd[0], f * fwd[1] - (1.0 - f), f * fwd[2])
        n = math.sqrt(sum(c * c for c in d))
        elbow = Q.add(shoulder, tuple(self.upper_arm * c / n for c in d))
        reach = self.forearm + self.grip_offset
        return Q.add(elbow, Q.rotate(ctrl_rot, (0.0, 0.0, -reach)))


def with_pitch_trim(mount: Q.Quat, degrees: float) -> Q.Quat:
    """Tilt the reported controller nose-up (positive) about its own X axis.

    VMT's Index emulation hands games the Index input profile's grip/tip poses,
    which are angled relative to the raw pose. If hands look pitched in games,
    trim it here."""
    return Q.normalize(Q.mul(mount, Q.axis_angle((1.0, 0.0, 0.0), math.radians(degrees))))


@dataclass
class ControllerOrientation:
    mount: Q.Quat = MOUNTS["flat-x-forward"]
    yaw_offset: Q.Quat = field(default=Q.IDENTITY)

    def raw(self, imu_quat: Q.Quat) -> Q.Quat:
        return Q.normalize(Q.mul(Q.mul(IMU_TO_VR, imu_quat), self.mount))

    def world(self, imu_quat: Q.Quat) -> Q.Quat:
        return Q.normalize(Q.mul(self.yaw_offset, self.raw(imu_quat)))

    def snap_yaw(self, imu_quat: Q.Quat, target_yaw: float) -> None:
        """Turn the controller's heading to target_yaw, keeping its tilt."""
        self.yaw_offset = Q.rot_y(target_yaw - Q.yaw(self.raw(imu_quat)))
