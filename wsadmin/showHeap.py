#!/usr/bin/env /was/bin/runwsadmin

servers = AdminConfig.list("Server").split("\n")
for s in servers:
	print "======== ", s
	jvm = AdminConfig.list("JavaVirtualMachine", s)
	print AdminConfig.show(jvm, "initialHeapSize maximumHeapSize")
	continue

