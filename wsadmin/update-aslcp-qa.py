#!env /usr/IBM/WebSphere/AppServer70/profiles/ryeqaslcpapp1/bin/wsadmin.sh -f

import sys, java
from java.util import Date,TimeZone
from java.text import SimpleDateFormat

if (len(sys.argv)) != 1:
   print >> sys.stderr, 'update-aslcp-qa.py: <ear-file>'
   sys.exit(1)

tz = TimeZone.getTimeZone("America/Sao_Paulo")
df = SimpleDateFormat()
df.setTimeZone(tz)

def log(msg):
   print >> sys.stderr, "=== ["+df.format(Date())+"]", msg

appname="ASLCP-EAR"
appear = sys.argv[0]
#appcluster = 
as1="ryeqaslcpapp1"
as2="ryeqaslcpapp2"
node1="ryeaxacqappbr1Node01"
node2="ryeaxacqappbr2Node01"

options = [ "-update", "-appname", appname, "-update.ignore.new", "-verbose" ]

#log("Stopping server "+as1)
#AdminControl.stopServer(as1,node1)
#log("Stopping server "+as2)
#AdminControl.stopServer(as2,node2)

log("Installing Application from "+appear)
AdminApp.install( appear, options )
log("Installation completed")

log("Saving configuration")
AdminConfig.save()

#log("Starting server "+as1)
#AdminControl.startServer(as1,node1)
#log("Starting server "+as2)
#AdminControl.startServer(as2,node2)


