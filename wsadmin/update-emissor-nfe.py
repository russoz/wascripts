# update-emissor-nfe.py 

import sys, java
from java.util import Date,TimeZone
from java.text import SimpleDateFormat

if (len(sys.argv)) != 1:
   print >> sys.stderr, 'update-emissor-nfe.py: <ear-file>'
   sys.exit(1)

tz = TimeZone.getTimeZone("America/Sao_Paulo")
df = SimpleDateFormat()
df.setTimeZone(tz)

def log(msg):
   print >> sys.stderr, "=== ["+df.format(Date())+"]", msg

appname="FiscalEmitter_QA"
appear = sys.argv[0]

options = [ "-update", "-appname", appname, "-update.ignore.new", "-verbose" ]

log("Installing Application from "+appear)
AdminApp.install( appear, options )
log("Installation completed")

log("Saving configuration")
AdminConfig.save()

