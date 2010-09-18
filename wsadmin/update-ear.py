# update-ear.py
#
# Alexei.Znamensky@cognizant.com
# May 18, 2010
#

import sys, java
from java.util import Date,TimeZone
from java.text import SimpleDateFormat

if len(sys.argv) != 2:
    print >> sys.stderr, 'update-ear.py: <enterprise-app> <ear-file>'
    sys.exit(1)

df = SimpleDateFormat()

def log(msg):
    print >> sys.stderr, "=== ["+df.format(Date())+"]", msg

appname=sys.argv[0]
appear =sys.argv[1]

options = [ "-update", "-appname", appname, "-update.ignore.new", "-verbose" ]

try:
    log("Installing Application from "+appear)
    AdminApp.install( appear, options )
    log("Installation completed")

    log("Saving configuration")
    AdminConfig.save()

except:
    print '************ EXCEPTION:'
    print sys.exc_info()
    print 'Modifications not saved'
    exit(1)



