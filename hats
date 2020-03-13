#!/usr/bin/python3 -u
#
# Copyright 2019 Benjamin Gilbert
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from beacontools import BeaconScanner, IBeaconFilter
from collections import namedtuple
import qhue
import time
import threading

# Hue
IP = "192.168.0.3"
TOKEN = "--TOKEN--"
LIGHT = '5'
TRANSITION_TIME = 5
bridge = qhue.Bridge(IP, TOKEN)
light = bridge.lights[LIGHT]

# Beacons
TIMEOUT = 5
SIGNAL_THRESHOLD = -70
UUID = 'e3901963-c4ac-40b7-a2bb-0c44808384c1'
Beacon = namedtuple("beacon", ["name", "state"])
BEACONS = {
    'b0:91:22:f7:6a:da': Beacon('bh3900-green', dict(on=True, bri=254, hue=24344, sat=252)),
    'b0:91:22:f7:68:85': Beacon('bh3812-purple', dict(on=True, bri=254, hue=49969, sat=221)),
    'b0:91:22:f7:64:fc': Beacon('bh3832-orange', dict(on=True, bri=254, hue=7760, sat=254)),
    'b0:91:22:f7:68:9c': Beacon('bh3882-yellow', dict(on=True, bri=254, hue=10823, sat=254)),
}

# State
prev_light_state = None
last_beacon = None
event = threading.Event()
lock = threading.Lock()
last_seen = {}  # addr -> time
signal = {}     # addr -> signal


# returns True if light changed
def set_light(beacon):
    global last_beacon, prev_light_state

    if beacon is last_beacon:
        return False

    if last_beacon is None:
        prev_light_state = bridge.lights()[LIGHT]['state']
        for garbage in 'colormode', 'mode', 'reachable':
            prev_light_state.pop(garbage, None)

    if beacon is not None:
        name = beacon.name
        state = beacon.state
    else:
        name = "default"
        state = prev_light_state

    print('Setting light to', name)
    light.state(transitiontime=TRANSITION_TIME, **state)
    last_beacon = beacon
    return True


def update():
    with lock:
        # GC
        remove = []
        for addr, last in last_seen.items():
            if last + TIMEOUT < time.time():
                remove.append(addr)
        for addr in remove:
            print('Clearing', BEACONS[addr].name)
            del signal[addr]
            del last_seen[addr]

        # Pick top
        by_signal = [(v, k) for k, v in signal.items()]
        by_signal.sort(reverse=True)
        beacon = None
        if by_signal:
            tgt_signal, tgt_addr = by_signal[0]
            if tgt_signal >= SIGNAL_THRESHOLD:
                beacon = BEACONS[tgt_addr]
        changed = set_light(beacon)

    if changed:
        # Wait for transition to finish before snapshotting prev state again
        time.sleep(.1 * (TRANSITION_TIME + 1))


def beacon_callback(bt_addr, rssi, _packet, _additional_info):
    beacon = BEACONS.get(bt_addr)
    with lock:
        name = beacon.name if beacon else bt_addr
        print("%s: %d" % (name, rssi))
        if beacon:
            last_seen[bt_addr] = time.time()
            signal[bt_addr] = rssi
    event.set()


def main():
    scanner = BeaconScanner(beacon_callback,
        device_filter=IBeaconFilter(uuid=UUID)
    )
    scanner.start()

    while True:
        event.wait(TIMEOUT)
        event.clear()
        update()


if __name__ == "__main__":
    main()
