# update-extrator.py

import sys, java
from java.util import Date,TimeZone
from java.text import SimpleDateFormat

if (len(sys.argv)) != 1:
   print >> sys.stderr, 'update-extrator.py: <ear-file>'
   sys.exit(1)

#tz = TimeZone.getTimeZone("America/Sao_Paulo")
df = SimpleDateFormat()
#df.setTimeZone(tz)

def log(msg):
   print >> sys.stderr, "=== ["+df.format(Date())+"]", msg

appname="FiscalExtractorQA"
appear = sys.argv[0]

options = [ "-update", "-appname", appname, "-update.ignore.new", "-verbose" ]

try:
   log("Installing Application from "+appear)
   AdminApp.install( appear, options )
   log("Installation completed")

   log("Saving configuration")
   AdminConfig.save()
except:
   print '************ EXCEPTION:', sys.exc_info()
   print 'Modifications not saved'
   exit(1)

