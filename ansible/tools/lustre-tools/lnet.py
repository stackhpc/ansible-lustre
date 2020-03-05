#!/usr/bin/env python
""" Export or lustre network and route information. Note sudo rights are required.

    Usage:
        lnet.py export [FILE]

    Export lnet configuration from the live system or from the specified yaml file.

    The data output is lnet and route information, similar to that from `lnetctl export` {1} but without
    transient info such as stats. Output is yaml format, suitable for `lnetctl import` {2}. Lists and
    mappings in the output are sorted to ensure predictable ordering.

    Notes
    1. The `lnetctl show` command does not provide route information.
    2. The `lnetctl export` command produces a different format from that documented for `lnetctl import`
       although tests that command will accept either format. This command uses the `lnetctl export` format
       as that contains more info (such as NIDs) which  while not *required* for lnet operation should allow
       unexpected configuration changes to be identified.

"""

from __future__ import print_function
__version__ = "0.0"

import sys, subprocess, pprint, datetime, os, difflib

# pyyaml:
from yaml import load, dump
try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper

# define fields to keep from `lnetctl export`:
ROUTES_FIELDS = ('gateway', 'hop', 'net')         # hop not  required (=> -1) but useful for diff?
LOCAL_NI_FIELDS = ('interfaces', 'nid', 'status') # status not required but diff? How do we set "down"?

def cmd(cmdline):
    """ Run a space-separated command and return its stdout/stderr.

        Uses shell, blocks until subprocess returns.
    """
    proc = subprocess.Popen(cmdline, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE) # need shell else lnetctl not found
    stdout, stderr = proc.communicate()
    return stdout, stderr

def deep_sort(data):
    """ In-place sort of any lists in a nested dict/list datastructure. """
    if isinstance(data, list):
        data.sort()
        for item in data:
            deep_sort(item)
    elif isinstance(data, dict):
        for item in data.itervalues():
            deep_sort(item)
    return None

def get_lnet_info():
    """ Read live lustre network and route information.
    
        Returns a dict containing nested dicts, lists and simple values. Lists are sorted.
     """

    # read the system's state as yaml:
    sout, serr = cmd('sudo lnetctl export')
    if serr is not None:
        raise Exception(serr)
    
    # convert to a python datastructure:
    data = load(sout, Loader=Loader)
    
    # filter:
    output = {'net':[], 'route':[]}
    if 'route' in data:
        for route in data['route']:
            output['route'].append(dict((k, v) for (k, v) in route.iteritems() if k in ROUTES_FIELDS))
    for net in data['net']:
        if net['net type'] != 'lo':
            outnet = {'net type':net['net type'],
                      'local NI(s)':[],}
            for local_ni in net['local NI(s)']:
                outnet['local NI(s)'].append(dict((k, v) for (k, v) in local_ni.iteritems() if k in LOCAL_NI_FIELDS))
            output['net'].append(outnet)
    
    deep_sort(data) # sort lists
    
    return output

def main():
    
    if len(sys.argv) == 2 and sys.argv[1] == 'export':
        live_data = get_lnet_info()
        live_yaml = dump(live_data, Dumper=Dumper, default_flow_style=False) # NB this sorts dicts
        print(live_yaml)
    else:
        print('ERROR: invalid commandline, usage follows:')
        print(__doc__)
        exit(1)

if __name__ == '__main__':
    main()
