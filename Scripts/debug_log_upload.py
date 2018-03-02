#!/usr/bin/env python
import sys
import os
import re
import commands
import subprocess
import argparse
import inspect    
import urllib2
import json

def fail(message):
    file_name = __file__
    current_line_no = inspect.stack()[1][2]
    current_function_name = inspect.stack()[1][3]
    print 'Failure in:', file_name, current_line_no, current_function_name
    print message
    sys.exit(1)


def execute_command(command):
    try:
        print ' '.join(command)
        output = subprocess.check_output(command)
        if output:
            print output
    except subprocess.CalledProcessError as e:
        print e.output
        sys.exit(1)

        
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Precommit cleanup script.')
    parser.add_argument('--file', help='used for starting a new version.')

    args = parser.parse_args()
    
    params_response = urllib2.urlopen("https://debuglogs.org/").read()
    
    params = json.loads(params_response)
    
    upload_url = params['url']
    upload_fields = params['fields']
    upload_key = upload_fields['key']
    upload_key = upload_key + os.path.splitext(args.file)[1]
    upload_fields['key'] = upload_key
    
    download_url = 'https://debuglogs.org/' + upload_key
    print 'download_url:', download_url
    
    curl_command = ['curl', '-v', '-i', '-X', 'POST']
    for field_name in upload_fields:
        field_value = upload_fields[field_name]
        curl_command.append('-F')
        curl_command.append("'%s=%s'" % (field_name, field_value, ))
    curl_command.append('-F')
    curl_command.append("'file=@%s'" % (args.file,))
    curl_command.append(upload_url)
    
    # execute_command(curl_command)
    print ' '.join(curl_command)

    print 'download_url:', download_url
    