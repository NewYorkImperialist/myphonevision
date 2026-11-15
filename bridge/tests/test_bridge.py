import math

from myphonevision_bridge import protocol as P
from myphonevision_bridge import quat as Q
from myphonevision_bridge.pose import IMU_TO_VR, MOUNTS, ArmModel, ControllerOrientation


def close(a, b, tol=1e-6):
    return all(abs(x - y) < tol for x, y in zip(a, b))


def controller_bytes(hand=1, quat=(1.0, 0.0, 0.0, 0.0), buttons=0):
    import struct
    return struct.pack("<HBBBBHffffhhHHH", P.MAGIC, P.VERSION, P.PKT_CONTROLLER, hand, 1, 7,
                       *quat, 32767, -32767, 65535, buttons, 0)


def test_frame_roundtrip_with_garbage_and_split_reads():
    payload = controller_bytes(buttons=P.BTN_A | P.BTN_SYSTEM)
    stream = b"\x00\xa5junk" + P.frame(payload) + b"\xa5\x5a\x03abc\x00" + P.frame(payload)
    dec = P.FrameDecoder()
    out = []
    for i in range(0, len(stream), 5):
        out += dec.feed(stream[i:i + 5])
    assert out == [payload, payload]
    pkt = P.parse_controller(out[0])
    assert pkt.hand == 1 and pkt.seq == 7 and pkt.gyro_calibrated
    assert close(pkt.stick, (1.0, -1.0)) and pkt.trigger == 1.0
    assert pkt.buttons == P.BTN_A | P.BTN_SYSTEM


def test_haptic_packet_size():
    assert len(P.build_haptic(0, 0.5, 0.1)) == 8


def test_imu_to_vr_maps_up_to_up():
    assert close(Q.rotate(IMU_TO_VR, (0, 0, 1)), (0, 1, 0))


def test_mounts_are_rotations():
    for q in MOUNTS.values():
        assert abs(sum(c * c for c in q) - 1) < 1e-9


def test_flat_controller_points_horizontally_and_snaps_to_head_yaw():
    o = ControllerOrientation(mount=MOUNTS["flat-x-forward"])
    imu = Q.axis_angle((0, 0, 1), 1.0)  # lying flat, some arbitrary heading
    fwd = Q.rotate(o.world(imu), (0, 0, -1))
    assert abs(fwd[1]) < 1e-9  # level
    o.snap_yaw(imu, 0.5)
    assert abs(Q.yaw(o.world(imu)) - 0.5) < 1e-9
    up = Q.rotate(o.world(imu), (0, 1, 0))
    assert close(up, (0, 1, 0))


def test_arm_model_puts_level_controller_in_front_and_to_the_side():
    arm = ArmModel()
    head = (0.0, 1.6, 0.0)
    right = arm.position(1, head, Q.IDENTITY, Q.IDENTITY)
    left = arm.position(0, head, Q.IDENTITY, Q.IDENTITY)
    assert right[0] > 0.1 and left[0] < -0.1
    assert right[2] < -0.2  # in front (-Z)
    assert 0.9 < right[1] < 1.4  # around waist-to-chest height
    turned = arm.position(1, head, Q.rot_y(math.pi / 2), Q.rot_y(math.pi / 2))
    assert turned[0] < -0.2  # head and hand turned left: hand now toward -X


def test_yaw_snap_works_pointing_at_floor_and_ceiling():
    o = ControllerOrientation(mount=MOUNTS["flat-x-forward"])
    for pitch in (-math.pi / 2 + 0.02, math.pi / 2 - 0.02):  # nose down, nose up
        # Device pointing near-vertically with its top facing heading 0.3 rad.
        dev = Q.mul(Q.rot_y(0.3), Q.axis_angle((1, 0, 0), pitch))
        imu = Q.mul(Q.mul(Q.conj(IMU_TO_VR), dev), Q.conj(o.mount))
        assert abs(Q.yaw(o.raw(imu)) - 0.3) < 1e-6
        o.snap_yaw(imu, 1.0)
        assert abs(Q.yaw(o.world(imu)) - 1.0) < 1e-6


def test_pitch_trim_raises_the_nose():
    from myphonevision_bridge.pose import with_pitch_trim
    o = ControllerOrientation(mount=with_pitch_trim(MOUNTS["flat-x-forward"], 20))
    level = Q.mul(Q.conj(IMU_TO_VR), Q.conj(MOUNTS["flat-x-forward"]))  # untrimmed: level
    fwd = Q.rotate(o.raw(level), (0, 0, -1))
    assert abs(math.degrees(math.asin(fwd[1])) - 20) < 1e-6


def test_hub_is_told_apart_by_its_frames():
    from myphonevision_bridge.preflight import hands_seen
    stream = b"\x00boot text\r\n" + P.frame(controller_bytes(hand=0)) + P.frame(controller_bytes(hand=1))
    assert hands_seen(stream) == {0, 1}
    assert hands_seen(b"stick raw    0    0 | trigger raw    0 (  0%)\r\n") == set()


def test_stick_hold_snaps_then_system():
    from myphonevision_bridge.__main__ import StickHold
    h, c = StickHold(), (0.0, 0.0)
    events = [h.update(True, c, i * 0.1) for i in range(40)]  # held 4 s, centered
    assert [(round(i * 0.1, 1), e) for i, e in enumerate(events) if e] == [(1.0, "snap"), (3.0, "system")]
    assert h.update(False, c, 4.1) is None and h.update(True, c, 4.2) is None  # release restarts it


def test_stick_hold_ignores_clicks_while_pushing():
    from myphonevision_bridge.__main__ import StickHold
    h = StickHold()
    assert not any(h.update(True, (0.0, 0.9), i * 0.1) for i in range(30))  # sprint-click
    assert not any(h.update(True, (0.0, 0.0), 3.0 + i * 0.1) for i in range(9))  # timer restarted


def test_squeeze_targets():
    from myphonevision_bridge.__main__ import SQUEEZE_TARGETS
    from myphonevision_bridge import vmt as V
    assert set(SQUEEZE_TARGETS["both"]) == {V.GRIP, V.TRIGGER}
    assert SQUEEZE_TARGETS["grip"] == (V.GRIP,)
    assert SQUEEZE_TARGETS["trigger"] == (V.TRIGGER,)
