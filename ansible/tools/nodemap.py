#!/usr/bin/env python
""" Export lustre nodemap information as yaml

    Usage:
        nodemap.py export
        nodemap.py diff FILE
    
    In the yaml output:
    - Simple values (i.e. which aren't themselves mappings or lists) are either ints or strings.
    - Lists and dicts are sorted to ensure predictable output.
"""
from __future__ import print_function
__version__ = "0.0"

import subprocess, pprint, sys, re, ast, difflib, datetime, os

# pyyaml:
from yaml import load, dump
try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper

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

def cmd(args):
    proc = subprocess.Popen(args, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE) # need shell else lctl not found
    stdout, stderr = proc.communicate()
    return stdout, stderr

def lctl_get_param(item, output):
    """ TODO:
        NB output gets modified!
        format: nested dicts, values may be nested list/dicts (including empty ones) or strings.
    """
    s, e = cmd("sudo lctl get_param '{item}'".format(item=item)) # need quoting around `item` to avoid shell expansion of ".*" !
    lines = s.strip().split('\n')
    accumulate = []
    for line in lines:
        #print(line)
        if line: # skip empty lines
            #print('line:', line)
            if '=' in line:
                
                # handle accumulated value lines from *previous* object:
                if accumulate:
                    prev_value = r[param] + ''.join(accumulate) # sometimes previous key=value ended"=[" so always prefix that
                    quoted_prev_value = re.sub(r'\s?([^\s:]+):\s?([^\s,]+)', r"'\1':'\2'", prev_value) # add quoting around dict values and keys
                    # turn it into python:
                    try:
                        py_prev_value = ast.literal_eval(quoted_prev_value)
                    except:
                        print('ERROR: failed when parsing', quoted_prev_value)
                        raise
                    
                    # store and reset:
                    r[param] = py_prev_value
                    accumulate = []

                # handle normal lines:
                param, _ , value = line.partition('=')
                parts = param.split('.')
                r = output
                for p in parts[:-1]:
                    r = r.setdefault(p, {})
                r[param] = value

            else:
                accumulate.append(line)
    return output
    
def get_nodemap_info():
    """ TODO: """
    output = {}
    lctl_get_param("nodemap.*", output)
    s, e = cmd("lctl nodemap_info",) # need quoting to avoid shell expansion!
    nodemaps = [n.split('.')[-1] for n in s.strip().split('\n')]
    #print(nodemaps)
    for nmap in nodemaps:
        lctl_get_param("nodemap.{nmap}.*".format(nmap=nmap), output)
    to_int(output)
    deep_sort(output)

    return output

def to_int(data, key_or_idx=None):
    """ Change ints-as-strs in nested python lists/dicts to ints
    
        NB: modifies data in place and returns None
    """
    if key_or_idx is None:
        value = data
    else:
        value = data[key_or_idx]
    if isinstance(value, list):
        for idx, v in enumerate(value):
            to_int(value, idx)
    elif isinstance(value, dict):
        for k, v in value.iteritems():
            to_int(value, k)
    elif isinstance(value, str):
        if value.isdigit():
            data[key_or_idx] = int(value)
        return

def main():

    # get system info:
    data = get_nodemap_info()
    
    live_time = datetime.datetime.now().isoformat()
    live_yaml = dump(data, Dumper=Dumper, default_flow_style=False)

    if len(sys.argv) == 2 and sys.argv[1] == 'export':
        print(live_yaml)
    elif len(sys.argv) == 3 and sys.argv[1] == 'diff':
            
        # use file as "from":
        saved_path = sys.argv[-1]
        saved_time = datetime.datetime.fromtimestamp(os.path.getmtime(saved_path)).isoformat()
        with open(saved_path) as f:
            # load it so we know its valid yaml and sorted:
            saved_data = load(f.read(), Loader=Loader)
            deep_sort(saved_data)
            saved_yaml = dump(saved_data, Dumper=Dumper, default_flow_style=False)
        
        # diff:
        for diff in difflib.unified_diff(saved_yaml.split('\n'), live_yaml.split('\n'), saved_path, 'live', saved_time, live_time):
            print(diff)

    else:
        print('ERROR: invalid commandline, help follows:')
        print(__doc__)
        exit(1)
    
if __name__ == '__main__':
    main()
