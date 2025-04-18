
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

char const *prog_name;

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
	enum { START, LINE_START, LINE } stage = START;
	int argc = 0;
	while (1) {
		ssize_t rcvd = recv(sock, out, (size_t)(out + sizeof(cmd->buf) - cmd->buf - 1), 0);
		if (rcvd < 0) {
			if (errno == EINTR)
				continue;
			else {
				if (errno == EPIPE)
					return 0;
				syslog(LOG_ERR, "command recv: %m");
				return -1;
			}
		}

		if (!rcvd)
			return 0;

		out += rcvd;

		while (parsed < out) {
			switch (stage) {
			case START:
				argc = *parsed++; // get number of args
				stage = LINE_START;

			case LINE_START:
				if (cmd->argc < countof(cmd->argv))
					cmd->argv[cmd->argc++] = parsed;
				stage = LINE;

			case LINE:
				if (!parsed[0]) { // zero char (end of line)
					if (!--argc)
						return cmd->argc;
					stage = LINE_START;
				}
				break;
			}
			++parsed;
		}
	}

	return 0;
}

/* -------------------------------------------------------------------------- */
static int create_pid_file(char const *pid_file)
{
	if (!pid_file || !pid_file[0])
		return -1;

	int fd = open(pid_file, O_CREAT|O_WRONLY, S_IRWXU);
	if (fd < 0) {
		syslog(LOG_ERR, "failed to create pid-file '%s' (%m)", pid_file);
		return -1;
	}

	char s[64];
	int len = snprintf(s, sizeof s, "%d\n", getpid());
	ssize_t wn = write(fd, s, len);
	if (wn < 0) {
		syslog(LOG_ERR, "failed to write pid-file '%s' (%m)", pid_file);
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

static char pid_file[256];

/* ------------------------------------------------------------------------ */
static void __die(void)
{
	kill(-2, SIGTERM); /* kill all(by sigterm) child processes */
	if (pid_file[0])
		unlink(pid_file);
}

#ifdef HOST_DEBUG
# define LOG_MODE   LOG_PID|LOG_PERROR
#else
# define LOG_MODE   LOG_PID
#endif

/* ------------------------------------------------------------------------ */
int main(int argc, char **argv)
{
	prog_name = strrchr(argv[0], '/') ?: argv[0];
	if (*prog_name == '/')
		++prog_name;

	openlog(prog_name, LOG_PID|LOG_PERROR, LOG_USER);

	pid_file[0] = 0;

#ifndef HOST_DEBUG
	unsigned nodaemon = 0;
	for (unsigned i = 1; i < argc; ++i) {
		if (!strcmp(argv[i], "-F"))
			nodaemon = 1;
		else
			if (!strcmp(argv[i], "-P")) {
				if (i + 1 < argc && argv[i + 1][0] != '-') {
					snprintf(pid_file, sizeof pid_file, "%s", argv[++i]);
					continue;
				}
				snprintf(pid_file, sizeof pid_file, "/var/run/%s.pid", prog_name);
				syslog(LOG_INFO, "pid_file: %s", pid_file);
			}
	}
	if (!nodaemon) {
		if (daemon(0, 1) < 0) {
			syslog(LOG_ERR, "daemonize failed (%m)");
			exit(1);
		}
	}
#endif

	init_signals();

	openlog(prog_name, LOG_PID|LOG_PERROR, LOG_DAEMON);

	if (pid_file[0]) {
		if (create_pid_file(pid_file) < 0)
			exit(1);
		atexit(__die);
	}

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
