# setRecoveryNode.py - must run with wsadmin
#
# Mostly from:
# http://www.ibm.com/developerworks/websphere/library/techarticles/0611_ashok/0611_ashok.html
#

#Script to create the recoveryNode custom property

#Step 1: Get a handle to the nodeagent
nodeagent = AdminConfig.getid('/Node:<node>/Server:nodeagent/')
print nodeagent

#Step 2: Get a handle to the ConfigSynchronizationService
syncservice = AdminConfig.list('ConfigSynchronizationService', nodeagent)
print syncservice

#Step 3: Create the custom property
AdminConfig.create("Property", syncservice, [["name", "recoveryNode"],["value", "true"]])

#Step 4: Save
AdminConfig.save

