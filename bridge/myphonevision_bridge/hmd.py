"""Headset pose from SteamVR, for the arm model and the yaw snap."""

from __future__ import annotations

from . import quat as Q


class FixedHmd:
    """Stand-in when SteamVR isn't reachable: a standing head looking down -Z."""

    def __init__(self, height: float = 1.6) -> None:
        self._pose = ((0.0, height, 0.0), Q.IDENTITY)

    def pose(self) -> tuple[Q.Vec, Q.Quat]:
        return self._pose


class SteamVrHmd:
    """Reads the HMD in the raw/uncalibrated universe, which is the space
    /VMT/Raw/Driver poses are given in. Verify on site: a controller posed
    0.3 m in front of the head (--debug-follow) should appear there."""

    def __init__(self) -> None:
        import openvr  # Windows + SteamVR only; `pip install openvr`

        self._openvr = openvr
        self._system = openvr.init(openvr.VRApplication_Background)
        self._last = FixedHmd().pose()

    def pose(self) -> tuple[Q.Vec, Q.Quat]:
        ovr = self._openvr
        poses = self._system.getDeviceToAbsoluteTrackingPose(
            ovr.TrackingUniverseRawAndUncalibrated, 0, ovr.k_unMaxTrackedDeviceCount
        )
        p = poses[ovr.k_unTrackedDeviceIndex_Hmd]
        if p.bPoseIsValid:
            m = p.mDeviceToAbsoluteTracking
            rows = [[m[i][j] for j in range(4)] for i in range(3)]
            self._last = ((rows[0][3], rows[1][3], rows[2][3]), Q.from_matrix(rows))
        return self._last

    def close(self) -> None:
        self._openvr.shutdown()
