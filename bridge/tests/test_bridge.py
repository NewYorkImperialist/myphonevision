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
