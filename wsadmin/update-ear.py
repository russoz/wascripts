# update-ear.py
#
# Alexei Znamensky
# russoz@gmail.com
#

import sys, java
from java.util import Date,TimeZone
from java.text import SimpleDateFormat

tzspec="America/Sao_Paulo"

if len(sys.argv) != 2:
    print >> sys.stderr, 'update-ear.py: <enterprise-app> <ear-file>'
    sys.exit(1)

tz = TimeZone.getTimeZone(tzspec)
df = SimpleDateFormat()
df.setTimeZone(tz)

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



