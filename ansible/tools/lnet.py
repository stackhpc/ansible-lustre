#!/usr/bin/env python
""" Export or compare lustre network and route information. Note sudo rights are required.

    Usage:
        lnet.py export [FILE]

            Export lnet configuration from the live system or from the specified yaml file.

        lnet.py diff FILE
    
            Diff the lnet configuration of the live system against that in the specified yaml file.

    The data output is lnet and route information, similar to that from `lnetctl export` {1} but without
    transient info such as stats. Output is yaml format, suitable for `lnetctl import` {2}. 
    Lists and dicts in the output are sorted so that the ordering is repeatable but this means output
    from exporting a file may not match the original file.

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

# define fields we want:
ROUTES_FIELDS = ('gateway', 'hop', 'net')         # hop not  required (=> -1) but useful for diff?
LOCAL_NI_FIELDS = ('interfaces', 'nid', 'status') # status not required but diff? How do we set "down"?

def cmd(args):
    proc = subprocess.Popen(args, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE) # need shell else lnetctl not found
    stdout, stderr = proc.communicate()
    return stdout, stderr

def deep_sort(data):
    """ In-place sort of any lists in a nested dict/list datastructure.
    
        NB pyyaml sorts dicts when dump()ing so only need to handle lists here.
    """
    if isinstance(data, list):
        data.sort()
        for item in data:
            deep_sort(item)
    elif isinstance(data, dict):
        for item in data.itervalues():
            deep_sort(item)
    return None

def get_lnet_info():
    """ TODO """
    # read the system's state as yaml:
    sout, serr = cmd('sudo lnetctl export')
    if serr is not None:
        raise Exception(serr)
    
    # convert to a python datastructure:
    data = load(sout, Loader=Loader)
    
    # filter:
    output = {'net':[], 'route':[]}
    for route in data['route']:
        output['route'].append(dict((k, v) for (k, v) in route.iteritems() if k in ROUTES_FIELDS))
    for net in data['net']:
        if net['net type'] != 'lo':
            outnet = {'net type':net['net type'],
                      'local NI(s)':[],}
            for local_ni in net['local NI(s)']:
                outnet['local NI(s)'].append(dict((k, v) for (k, v) in local_ni.iteritems() if k in LOCAL_NI_FIELDS))
            output['net'].append(outnet)
    
    # sort:
    deep_sort(data)
    
    return output

def main():

    # get system info:
    live_data = get_lnet_info()
    live_time = datetime.datetime.now().isoformat()
    live_yaml = dump(live_data, Dumper=Dumper, default_flow_style=False)

    if len(sys.argv) == 2 and sys.argv[1] == 'export':
        print(live_yaml)
    
    elif len(sys.argv) == 3:
        
        # use file as "from":
        saved_path = sys.argv[-1]
        saved_time = datetime.datetime.fromtimestamp(os.path.getmtime(saved_path)).isoformat()
        with open(saved_path) as f:
            # load it so we know its valid yaml and sorted:
            saved_data = load(f.read(), Loader=Loader)
            deep_sort(saved_data)
            saved_yaml = dump(saved_data, default_flow_style=False)
        
        if sys.argv[1] == 'export':
            print(saved_yaml)
        elif sys.argv[1] == 'diff':
            
            for diff in difflib.unified_diff(saved_yaml.split('\n'), live_yaml.split('\n'), saved_path, 'live', saved_time, live_time):
                print(diff)
        
    else:
        print('ERROR: invalid commandline, help follows:')
        print(__doc__)
        exit(1)
    

    
    


if __name__ == '__main__':
    main()
