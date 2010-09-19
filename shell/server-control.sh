#!/bin/sh -e 'echo Do not run this >&2; exit 1'
#
# Alexei Znamensky <russoz@gmail.com>
#
# Feel free to send suggestions, comments. Flames go to /dev/null.
#

[ -n "${_SERVER_CONTROL}" ] && return
_SERVER_CONTROL=1
_scriptname=$(echo $0|sed -e 's/^.*\///')

_msg() {
  echo "$@" >&2
}

_debug() {
  [ -z "$DEBUG" ] && return
  _msg 'DEBUG:' "$@"
}

_mustberoot() {
  [ $(id -u) = 0 ] || {
    _msg "ERROR: Must be root!"
    exit 1
  }
}

_check_user_pass() {
  user="$1"; shift
  pass="$1"; shift

  [ -n "$user" -a -n "$pass" ] && return 0
  [ -z "$user" -a -z "$pass" ] && return 0
  return 1
}

##############################################################################

_logfile() {
  file="$1"; shift

  if [ -n "$1" ]; then
    "$@" "$file"
  elif [ -x /opt/freeware/bin/tail ]; then
    /opt/freeware/bin/tail -F "$file"
  else
    /usr/bin/tail -f "$file"
  fi
}

##############################################################################

_was_ps() {
  root="$1"
  server="$2"

  /bin/ps -feda \
    | perl -nle 'BEGIN {
          $r=shift;
          $r =~ s|/profiles|(/bin/..)?/profiles|;
          $srv=shift;
        }
      next unless m|$r/config\s+\S+\s+\S+\s+$srv\s*$|;
      print' "${root}" "${server}"
}

_was_kill() {
  root="$1"
  server="$2"

  pid=$(_was_ps "${root}" "${server}" | awk '{ print $2 }')
  [ -z "$pid" ] && {
    _msg "Ahn? It looks like it is already STOPPED. Please check."
    return 1
  }

  pidfile="${root}/logs/${server}/${server}.pid"
  waspid=$(cat ${pidfile})
  [ "$pid" != "$waspid" ] && {
    _msg "ERROR: pid=${waspid} in ${pidfile}"
    _msg "ERROR: pid=${pid} calculated"
    return 1
  }

  _msg "Sending SIGTERM to pid" $pid
  kill -TERM $pid
  _msg "Sleeping 20 seconds"
  sleep 20
  proc=$(_was_ps "${root}" "${server}")
  [ -z "$proc" ] && { _msg "Dead."; return 0; }
  _debug "proc=$proc"

  _msg "Sending SIGKILL to pid" $pid
  kill -KILL $pid
  sleep 3
  proc=$(_was_ps "${root}" "${server}")
  [ -z "$proc" ] && { _msg "Dead."; return 0; }

  _msg "Hmmm... not dead yet. Trying again in 5 seconds."
  sleep 5
  _msg "Sending SIGKILL to pid" $pid
  kill -KILL $pid
  sleep 3
  proc=$(_was_ps "${root}" "${server}")
  [ -z "$proc" ] && { _msg "Now it is dead."; return 0; }

  _msg "It seems to be an immortal:"
  _msg "${proc}"
  return 1
}

_was_env() {
  file="$1"

  /usr/bin/cat ${file} \
    | /usr/bin/awk '/Start.*Environment/,/End.*Environment/ { print }'
}

_run() {
  user="$1"; shift

  _debug "user: $user"
  _debug "$*"
  if [ -n "$user" ]; then
    su - "$user" -c "$*"
  else
    "$@"
  fi
}

_was_switch() {
  type="$1"; shift
  unixid="$1"; shift
  root="$1"; shift
  comm="$1"; shift
  server="$1"; shift

  case "${type}" in
    d|D) _start=startManager.sh; _stop=stopManager.sh; _status_srv=dmgr ;;
    n|N) _start=startNode.sh; _stop=stopNode.sh; _status_srv=nodeagent ;;
    s|S) _start=startServer.sh; _stop=stopServer.sh; _status_srv="${server}" ;;
  esac   

  case "${comm}" in
    start)      _run "$unixid" ${root}/bin/${_start} ${server} $@ ;;
    stop)       _run "$unixid" ${root}/bin/${_stop}  ${server} $@ ;;

    status)     pid=$(_was_ps "${root}" "${_status_srv}" | awk '{ print $2 }')
                [ -z "$pid" ] && {
                  _msg "No process found (root=$root; server=$_status_srv)"
                  return 1
                }
                _msg "Process found running with PID: $pid"
                _run "$unixid" ${root}/bin/serverStatus.sh ${_status_srv} $@ ;;

    status-all) _run "$unixid" ${root}/bin/serverStatus.sh -all $@ ;;
    restart)    _run "$unixid" ${root}/bin/${_stop} ${server} $@ \
                  && sleep 5 \
                  && _run "$unixid" ${root}/bin/${_start} ${server} $@ ;;
    log)        _logfile ${root}/logs/${_status_srv}/SystemOut.log "$@" ;;
    err)        _logfile ${root}/logs/${_status_srv}/SystemErr.log "$@" ;;
    kill)       _was_kill "${root}" "${server}" ;;
    version)    _run "$unixid" ${root}/bin/versionInfo.sh ;;
    env)        _was_env ${root}/logs/${_status_srv}/SystemOut.log ;;
  esac
}

##############################################################################

usage_wasctl() {
  [ "$1" = "-n" ] && { svcname="$2"; shift; shift; }
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOU

USAGE
    ${svcname:-_wasctl [options]} command
    
DESCRIPTION
    Controls a WAS instance

COMMAND
    help        Prints this message
    start       Starts the application server
    stop        Stops the application server
    restart     Stops and starts the application server
    status      Prints status for the application server
    status-all  Prints status for all application servers
    log [cmd]   Starts a 'tail -f' or cmd on the server's SystemOut.log
    err [cmd]   Starts a 'tail -f' or cmd on the server's SystemErr.log
    kill        Attempts to kill the application server
    version     Prints WebSphere version being used

EOU

  [ -z "${svcname}" ] && {
    cat >&2 <<EOM
OPTIONS
    -r  <WAS profile root> (mandatory)
        Root directory for the working WAS profile
    -n  <name> (optional)
        Service name (usually \${0##*/})
    -s  <server> (mandatory)
        Server instance to apply command
    -u  <user> (optional)
        User name for WAS
    -p  <password> (optional)
        Password for WAS
    -U  <user> (optional)
        Local OS user

EOM
  }
  exit 1
}

_wasctl() {
  set -- $(getopt n:r:s:u:p:U: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_wasctl; return 1; }
  _mustberoot
  
  unset name root server user pass UP comm
  name=${_scriptname}
  while [ "$1" != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      -s)   server="$1"; shift ;;
      -u)   user="$1"; shift ;;
      -p)   pass="$1"; shift ;;
      -U)   unixid="$1"; shift ;;
      *)    usage_wasctl "_wasctl: Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ]   && { usage_wasctl "_wasctl: Must specify a name"  ; }
  [ -z "${root}" ]   && { usage_wasctl "_wasctl: Must specify a root"  ; }
  [ -d "${root}" ]   || { usage_wasctl "_wasctl: Invalid root: ${root}"; }
  [ -z "${server}" ] && { usage_wasctl "_wasctl: Must specify a server"; }

  _check_user_pass "${user}" "${pass}" || {
    usage_wasctl "_wasctl: Must specify both user and password"
  }

  [ -z "${user}" ] && UP="-username ${user} -password ${pass}"

  comm="$1"; shift
  _msg "=================== ${name}(${server}): ${comm}"

  case "${comm}" in
    start|stop|status|status-all|restart|log|err|kill|version|env)
          _was_switch s "${unixid}" "${root}" "${comm}" "${server}" $UP ;;

    help) usage_wasctl -n ${name} ;;
    *)    _msg "usage: ${name}" \
            "(help|start|stop|restart|status|status-all|log|err|kill)"
          return 1 ;;
  esac
}

##############################################################################

usage_wasnodectl() {
  [ "$1" = "-n" ] && { svcname="$2"; shift; shift; }
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOU

USAGE
    ${svcname:-_wasnodectl [options]} command

DESCRIPTION
    Controls a WAS node agent

COMMAND
    help        Prints this message
    start       Starts the node agent
    stop        Stops the node agent
    restart     Stops and starts the node agent
    status      Prints status for the node agent
    status-all  Prints status for all application servers
    log [cmd]   Starts a 'tail -f' or cmd on the agent's SystemOut.log
    err [cmd]   Starts a 'tail -f' or cmd on the agent's SystemErr.log
    kill        Attempts to kill the node agent
    version     Prints WebSphere version being used

EOU
  [ -z "${svcname}" ] && {
    cat >&2 <<EOM
OPTIONS
    -r  <WAS profile root> (mandatory)
        Root directory for the working WAS profile
    -n  <name> (optional)
        Service name (usually \${0##*/})
    -u  <user> (optional)
        User name for WAS
    -p  <password> (optional)
        Password for WAS
    -U  <user> (optional)
        Local OS user

EOM
  }
  exit 1
}

_wasnodectl() {
  set -- $(getopt D:P:n:r:u:p:U: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_wasnodectl; return 1; }
  _mustberoot
  
  unset name root user pass UP comm
  name=${_scriptname}
  while [ "$1" != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      -u)   user="$1"; shift ;;
      -p)   pass="$1"; shift ;;
      -D)   dmgr="$1"; shift ;;
      -P)   port="$1"; shift ;;
      -U)   unixid="$1"; shift ;;
      *)    usage_wasnodectl "Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ] && { usage_wasnodectl "_wasnodectl: Must specify a name"; }
  [ -z "${root}" ] && { usage_wasnodectl "_wasnodectl: Must specify a root"; }
  [ -d "${root}" ] || { usage_wasnodectl "_wasnodectl: Invalid root: ${root}"; }

  _check_user_pass "${user}" "${pass}" || {
    usage_wasnodectl "_wasnodectl: Must specify both user and password"
  }

  [ -z "${user}" ] && UP="-username ${user} -password ${pass}"

  comm="$1"; shift
  _msg "=================== ${name}: ${comm}"
  [ -z "${dmgr}" ] && {
    _msg "${name}: No dmgr passed. Command 'sync' not available·"
  }

  case "${comm}" in
    start|stop|status|status-all|restart|log|err|kill|version|env)
          _was_switch n "${unixid}" "${root}" "${comm}" "${server}" $UP ;;

    help) usage_wasnodectl -n ${name} ;;
    sync) [ -n "${dmgr}" ] && {
            _run "${unixid}" ${root}/bin/stopNode.sh ${UP} \
              && _run "${unixid}" ${root}/bin/syncNode.sh ${dmgr} ${port} ${UP} \
              && _run "${unixid}" ${root}/bin/startNode.sh ${UP}
          } ;;
    *)    _msg "usage: ${name}" \
            "(help|start|stop|restart|status|status-all|log|err|kill)"
          return 1 ;;
  esac
}

##############################################################################

usage_wasdmgrctl() {
  [ "$1" = "-n" ] && { svcname="$2"; shift; shift; }
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOU

USAGE
    ${svcname:-_wasdmgrctl [options]} command

DESCRIPTION
    Controls a WAS deployment manager

COMMAND
    help        Prints this message
    start       Starts the deployment manager
    stop        Stops the deployment manager
    restart     Stops and starts the deployment manager
    status      Prints status for the deployment manager
    status-all  Prints status for all application servers
    log         Starts a 'tail -f' on the dmgr's SystemOut.log
    err         Starts a 'tail -f' on the dmgr's SystemErr.log
    kill        Attempts to kill the node deployment manager
    version     Prints WebSphere version being used

EOU
  [ -z "${svcname}" ] && {
    cat >&2 <<EOM
OPTIONS
    -r  <WAS profile root> (mandatory)
        Root directory for the working WAS profile
    -n  <name> (optional)
        Service name (usually \${0##*/})
    -u  <user> (optional)
        User name for WAS
    -p  <password> (optional)
        Password for WAS
    -U  <user> (optional)
        Local OS user

EOM
  }
  exit 1
}

_wasdmgrctl() {
  set -- $(getopt n:r:u:p:U: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_wasdmgrctl; return 1; }
  _mustberoot
  
  unset name root user pass UP comm
  name=${_scriptname}
  while [ "$1" != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      -u)   user="$1"; shift ;;
      -p)   pass="$1"; shift ;;
      -U)   unixid="$1"; shift ;;
      *)    usage_wasdmgrctl "Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ] && { usage_wasdmgrctl "_wasdmgrctl: Must specify a name"; }
  [ -z "${root}" ] && { usage_wasdmgrctl "_wasdmgrctl: Must specify a root"; }
  [ -d "${root}" ] || { usage_wasdmgrctl "_wasdmgrctl: Invalid root: ${root}"; }

  _check_user_pass "${user}" "${pass}" || {
    usage_wasdmgrctl "_wasdmgrctl: Must specify both user and password"
  }

  [ -z "${user}" ] && UP="-username ${user} -password ${pass}"

  comm="$1"; shift
  _msg "=================== ${name}: ${comm}"

  case "${comm}" in
    start|stop|status|status-all|restart|log|err|kill|version|env)
          _was_switch d "${unixid}" "${root}" "${comm}" "" $UP ;;

    help) usage_wasdmgrctl -n ${name} ;;
    *)    _msg "usage: ${name}" \
            "(help|start|stop|restart|status|status-all|log|err|kill)"
          return 1 ;;
  esac
}

##############################################################################

usage_ihsctl() {
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOM
USAGE
    _ihsctl [options] command

DESCRIPTION
    Controls an IHS instance

COMMAND
    start       Starts the IHS server
    stop        Stops the IHS server
    graceful    Graceful restart
    restart     Stops and starts the IHS server
    status      Prints status for the IHS server

    admin-start       Starts the IHS administrative server
    admin-stop        Stops the IHS administrative server
    admin-graceful    Graceful administrative server
    admin-restart     Stops and starts the IHS administrative server
    admin-status      Prints status for the IHS administrative server

OPTIONS
    -n  <name> (mandatory)
        Service name (usually \${0##*/})
    -r  <IHS root> (mandatory)
        IHS installation root directory

EOM
  exit 1
}

_ihsctl() {
  set -- $(getopt n:r: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_ihsctl; return 1; }
  _mustberoot
  
  unset name root comm
  name=${_scriptname}
  while [ $1 != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      *)    usage_ihsctl "Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ] && { usage_ihsctl "_ihsctl: Must specify a name"; }
  [ -z "${root}" ] && { usage_ihsctl "_ihsctl: Must specify a root"; }

  comm="$1"; shift
  _msg "=================== ${name}: ${comm} $@"

  case "${comm}" in
    start|stop|graceful|status)
                    ${root}/bin/apachectl ${comm}                  ;;
    restart)        ${root}/bin/apachectl stop \
                      && sleep 5 \
                      && ${root}/bin/apachectl start               ;;
    log)            _logfile ${root}/logs/access_log "$@"          ;;
    err)            _logfile ${root}/logs/error_log  "$@"          ;;
                      
    admin-start|admin-stop|admin-graceful|admin-status)
                    ${root}/bin/adminctl $(echo ${comm}|sed -e 's/admin-//') ;;
    admin-restart)  ${root}/bin/adminctl stop \
                      && ${root}/bin/adminctl start                ;;
    admin-log)      _logfile ${root}/logs/admin_access_log "$@"    ;;
    admin-err)      _logfile ${root}/logs/admin_error?log  "$@"    ;;
                      
    version)        ${root}/bin/apachectl -v                       ;;
    
    *) _msg "usage: ${name} [admin-](start|stop|graceful|restart|status)"
       return 1 ;;
  esac
}

##############################################################################

usage_ldapctl() {
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOM
USAGE
    _ldapctl [options] command
    
DESCRIPTION
    Controls a Tivoli Directory Server (TDS) instance

COMMAND
    start       Starts the TDS instance
    stop        Stops the TDS instance
    restart     Stops and starts the TDS instance
    status      Prints status for the TDS instance

OPTIONS
    -n  <name> (mandatory)
        Service name (usually \${0##*/})
    -r  <TDS root> (mandatory)
        Root directory for the TDS installation
    -i  <instance> (mandatory)
        TDS instance to apply command

EOM
  exit 1
}

_ldapctl() {
  set -- $(getopt n:r:i:u:p: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_ldapctl; return 1; }
  _mustberoot
  
  unset name root inst comm
  name=${_scriptname}
  while [ $1 != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      -i)   inst="$1"; shift ;;
      *)    usage_ldapctl "Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ] && { usage_ldapctl "_ldapctl: Must specify a name"; }
  [ -z "${root}" ] && { usage_ldapctl "_ldapctl: Must specify a root"; }
  [ -z "${inst}" ] && { usage_ldapctl "_ldapctl: Must specify an instance"; }

  comm="$1"; shift
  _msg "=================== ${name}(${inst}): ${comm}"

  case "${comm}" in
    start|stop|status)
             ${root}/bin/idsdirctl ${comm}  -- -I ${inst} ;;
    restart) ${root}/bin/idsdirctl stop   -- -I ${inst} \
               && ${root}/bin/idsdirctl start -- -I ${inst} ;;

    *)       _msg "usage: ${name} (start|stop|restart|status)"
             return 1 ;;
  esac
}

##############################################################################

usage_mqctl() {
  [ -n "$1" ] && _msg 'ERROR:' "$@"
  cat >&2 <<EOM
USAGE
    _mqctl [options] command
    
DESCRIPTION
    Controls a MQ instance

COMMAND
    start       Starts the MQ instance
    stop        Stops the MQ instance
    restart     Stops and starts the MQ instance
    status      Prints status for the MQ instance

OPTIONS
    -n  <name> (mandatory)
        Service name (usually \${0##*/})
    -r  <MQ root> (mandatory)
        Root directory for the MQ installation
    -m  <queue manager> (mandatory)
        MQ Queue Manager to apply command
    -U  <user> (optional)
        User ID to issue MQ commands

EOM
  exit 1
}

_mqctl() {
  set -- $(getopt n:r:m:U: $*)
  # check result of parsing
  [ $? != 0 ] && { usage_mqctl; return 1; }
  _mustberoot

  unset name root qmgr user comm
  name=${_scriptname}
  while [ $1 != -- ]; do
    flag="$1"; shift
    case ${flag} in
      -n)   name="$1"; shift ;;
      -r)   root="$1"; shift ;;
      -m)   qmgr="$1"; shift ;;
      -U)   unixid="$1"; shift ;;
      *)    usage_mqctl "Invalid option $1" ;;
    esac
  done
  shift   # skip the --

  [ -z "${name}" ] && { usage_mqctl "_mqctl: Must specify a name"; }
  [ -z "${root}" ] && { usage_mqctl "_mqctl: Must specify a root"; }
  [ -z "${qmgr}" ] && { usage_mqctl "_mqctl: Must specify a qmgr"; }

  comm="$1"; shift
  _msg "=================== ${name}(${qmgr}): ${comm}"

  case "${comm}" in
    start)    _run "${unixid}" ${root}/bin/strmqm      ${qmgr}
              _run "${unixid}" ${root}/bin/strmqcsv    ${qmgr}
              _run "${unixid}" ${root}/bin/runmqlsr -m ${qmgr} -t TCP &   ;;

    stop)     _run "${unixid}" ${root}/bin/endmqlsr -m ${qmgr}
              _run "${unixid}" ${root}/bin/endmqcsv -c ${qmgr}
              _run "${unixid}" ${root}/bin/endmqm      ${qmgr}   ;;

    status)   _run "${unixid}" ${root}/bin/dspmq -m    ${qmgr}
              _run "${unixid}" ${root}/bin/dspmqcsv    ${qmgr}   ;;

    restart)  #stop
              _run "${unixid}" ${root}/bin/endmqlsr -m ${qmgr}
              _run "${unixid}" ${root}/bin/endmqcsv -c ${qmgr}
              _run "${unixid}" ${root}/bin/endmqm      ${qmgr}
            
              #start
              _run "${unixid}" ${root}/bin/strmqm      ${qmgr}
              _run "${unixid}" ${root}/bin/strmqcsv    ${qmgr}
              _run "${unixid}" ${root}/bin/runmqlsr -m ${qmgr} -t TCP &   ;;

    *)        _msg "usage: ${name} (start|stop|restart|status)"
              return 1 ;;
esac

}

##############################################################################

