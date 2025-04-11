# `superd` scheduler/monitor

Realy small cron like tasks(processes) scheduler/monitor but without config file daemon.

## Functions
	* Delayed run processes;
 	* Periodicaly run processes;
  	* Monitoring of started processes and restart it in case of crash


## `superd` daemon

```
# superd -F -P pid_file
Usage:
	-F   Run in foreground mode (no as daemon);
	-P   store PID of superd to the file.
```

## `super` control utility

`super <command> <id> ...`

### Commands
```
# super -q <action> <id> [-w] [-d <delay>] [-p <period>] <command-line>
options:
  -q           -- quiet (hide of error messages)
actions:
  sched <id> [-l] [-q] [-w] [-d <delay>] [-p <period>] <command-line>
	-- schedule the program to run once or periodicaly
  watch <id> [-l] [-q] [-d <delay>] <command-line>
	-- watch for the program for crash and restart it
  set <id> [-q] [-d <delay>] [-p <period>]
	-- change options of a queued program
  stop <id>
	-- stop a queued program
  start <id> [-d <delay>]
	-- start a queued program
  restart <id> [-d <delay>]
	-- stop and start a queued program
  list 
	-- list current queue
  remove <id> [-l]
	-- stop and remove a queued item
actions options:
  -q           -- redirect all output to /dev/null
  -l           -- leave the old queued item to die by it self
  -w           -- wait for exit
  -d <delay>   -- start delay (in seconds)
  -p <period>  -- run program periodicaly (in seconds)
```
