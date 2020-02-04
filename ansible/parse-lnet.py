#!/usr/bin/env python
""" Read output from `lnetctl export` and parse it into lnetc.conf format

    Usage:
        parse-lnet FILE
    
    TODO: Read stdin
"""

import yaml
import sys

with open(sys.argv[1], 'r') as stream:
    data = yaml.safe_load(stream)
    if 'net' in data:
        print 'net:'    
        for net in data['net']:
            if "lo" not in net['net type']:
                print '    - net:', net['net type']
                print '      local NI(s):'
                for ni in net['local NI(s)']:
                    print '        - nid:', ni['nid']
                    print '          interfaces:'
                    for k, v in ni['interfaces'].iteritems():
                        print '              %i: %s' % (k, v)
    if 'route' in data:
        print 'route:'
        for route in data['route']:
            print '    - net:', route['net']
            print '      gateway:', route['gateway']
