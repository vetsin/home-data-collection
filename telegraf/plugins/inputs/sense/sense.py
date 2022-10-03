from datetime import datetime
from typing import Dict
import os
import time

from sense_energy import Senseable
from telegraf_pyplug.main import print_influxdb_format, utc_now

# debugging sometimes
#def print_influxdb_format(*args, **kwargs):
#    pass

SENSE_MAINS='sense_mains'
SENSE_DEVICES='sense_devices'
LEG1='L1'
LEG2='L2'

def _output_voltage(data):
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG1),
        fields=dict(voltage=data['voltage'][0]),
        nano_timestamp=data['epoch']
    )
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG2),
        fields=dict(voltage=data['voltage'][1]),
        nano_timestamp=data['epoch']
    )

def _output_watts(data):
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG1),
        fields=dict(watts=data['watts'][1]),
        nano_timestamp=data['epoch']
    )
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG2),
        fields=dict(watts=data['watts'][1]),
        nano_timestamp=data['epoch']
    )

def _output_solar_aux(data):
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG1),
        fields=dict(solar_watts=data['aux']['solar'][0]),
        nano_timestamp=data['epoch']
    )
    print_influxdb_format(
        measurement=SENSE_MAINS,
        tags=dict(leg=LEG2),
        fields=dict(solar_watts=data['aux']['solar'][1]),
        nano_timestamp=data['epoch']
    )


def nil(obj, field=None):
    if not obj:
        return True
    if field and field not in obj:
        return True
    o = obj[field] if field else obj
    if o is None:
        return True
    if getattr(o, '__len__', None):
        if len(o) == 0:
            return True
    return False

def update_to_influxdb(data):
    if not nil(data, 'epoch'):
        # correct it to nanosecond time
        data['epoch'] = data['epoch']*10**9

        if not nil(data, 'voltage'):
            _output_voltage(data)
        if not nil(data, 'watts'):
            _output_watts(data)
        if not nil(data, 'aux') and not nil(data['aux'], 'solar'):
            _output_solar_aux(data)

        fields={}
        def field_add(f):
            if not nil(data, f): fields[f] = data[f]
        any(map(field_add, ['hz', 'c', 'w', 'solar_w', 'grid_w', 'solar_c', 'solar_pct', 'd_w', 'd_solar_w', 'frame', 'defaultCost']))
        if not nil(fields):
            print_influxdb_format(
                measurement=SENSE_MAINS,
                tags=dict(),
                fields=fields,
                nano_timestamp=data['epoch']
            )

        # devices
        for device in data['devices']:
            dtags = dict(id=device['id'],name=device['name'])
            # shove all uncomplex tags in
            dtags.update(**{ k:v for (k,v) in device['tags'].items() if not isinstance(v, (list, dict)) })

            # add these fields, if they exist
            dfields = {}
            def dfield_add(f):
                if not nil(device, f): dfields[f] = device[f]
            any(map(dfield_add, ('w', 'i', 'v', 'e', 'ao_w')))
            if not nil(dfields):
                print_influxdb_format(measurement=SENSE_DEVICES, tags=dtags, fields=dfields, nano_timestamp=data['epoch'])


    

def main() -> None:
    sense = Senseable()
    sense.load_auth(os.environ['SENSE_TOKEN'], os.environ['SENSE_USER_ID'], os.environ['SENSE_ID'])

    print_influxdb_format(
        measurement="sense_collector",
        tags=dict(source='sense.py', event='started'),
        fields=dict(time=time.mktime(utc_now().timetuple())*1000)
    )

    for result in sense.get_realtime_stream():

        start = time.time_ns()
        update_to_influxdb(result)
        end = time.time_ns()
        print_influxdb_format(
            measurement="sense_collector",
            tags=dict(source='sense.py', event='update_to_influxdb'),
            fields=dict(duration=end-start)
        )

if __name__ == '__main__':
    main()