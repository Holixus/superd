
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/sysinfo.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <resolv.h>
#include <fcntl.h>
#include <strings.h>
#include <string.h>
#include <errno.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <syslog.h>
#include <ctype.h>

#include "config.h"
#include "super.h"

#define LOG_NAME "superd"

#include "time.i"
#include "queue.i"
#include "sched.i"
#include "commands.i"
#include "signals.i"

#ifndef ACCEPT_QUEUE_LENGTH
# define ACCEPT_QUEUE_LENGTH 16
#endif

/* ------------------------------------------------------------------------ */
static int open_socket()
{
	unlink(SUPERD_SOCKET);

	int sock = socket(AF_LOCAL, SOCK_STREAM, 0);

	struct sockaddr_un addr;
	bzero(&addr, sizeof(addr));
	addr.sun_family = AF_LOCAL;
	strcpy(addr.sun_path, SUPERD_SOCKET);
	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
		perror("bind AF_UNIX");
		return -1;
	}

	if (listen(sock, ACCEPT_QUEUE_LENGTH) != 0) {
		perror("listen");
		return -1;
	}
	return sock;
}

/* ------------------------------------------------------------------------ */
static int receive_command(int sock, cmd_t *cmd)
{
	memset(cmd, 0, sizeof(*cmd));
	char *out = cmd->buf, *parsed = cmd->buf;
	int line_start = 1, start = 1, argc = 0;
	while (1) {
		if (parsed >= out) {
			ssize_t rcvd = recv(sock, out, (size_t)(out + sizeof(cmd->buf) - cmd->buf - 1), 0);

			if (rcvd < 0) {
				if (errno == EINTR)
					continue;
				else {
					perror("recv");
					if (errno == EPIPE)
						return 0;
					return -1;
				}
			}

			if (!rcvd)
				return 0;

			out[rcvd] = 0;
			out += rcvd;
		}

		if (start)
			start = (argc = *parsed++, 0);

		if (line_start) {
			if (cmd->argc < countof(cmd->argv))
				cmd->argv[cmd->argc++] = parsed;
			line_start = 0;
		}
		if (!parsed[0]) {
			if (!--argc)
				return cmd->argc;
			line_start = 1;
		}
		++parsed;
	}

	return 0;
}

/* ------------------------------------------------------------------------ */
static void __die()
{
	kill(-2, SIGTERM); /* kill all(by sigterm) child processes */
}

/* ------------------------------------------------------------------------ */
int main(int argc, char **argv)
{
#ifndef HOST_DEBUG
	if (argc < 2 || strcmp(argv[1], "-F")) {
		if (daemon(0, 1) < 0) {
			syslog(LOG_ERR, "daemonize failed (%m)");
			exit(1);
		}
	}
#endif

	init_signals();

#ifdef HOST_DEBUG
# define LOG_MODE   LOG_PID|LOG_PERROR
#else
# define LOG_MODE   LOG_PID
#endif
	openlog(LOG_NAME, LOG_MODE, LOG_DAEMON);
	atexit(__die);

	queues_restore(BACKUP_FILENAME);

_reopen:;
	int sock = open_socket();
	if (sock < 0) {
		syslog(LOG_WARNING, "can't open listen socket (%m)");
		return -1;
	}
	//_trace("socket: opened\n");

	for (;;) {
		check_signals();
		//_trace("socket: accept\n");
		int connsock = accept(sock, NULL, NULL);
		if (connsock < 0) {
			if (errno == EINTR) {
				continue;
			} else {
				syslog(LOG_WARNING, "listen socket failed (%m)");
				close(sock);
				goto _reopen;
			}
		}
		//_trace("socket: receive_command\n");
		cmd_t cmd;
		int cnt = receive_command(connsock, &cmd);
		if (cnt < 0) {
			close(connsock); /* failed to receive a command */
			continue;
		}

		exec_command(connsock, &cmd); /* close connsock by it self */
	}

	close(sock);
	return 0;
}
