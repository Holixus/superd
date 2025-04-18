
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <resolv.h>
#include <strings.h>
#include <string.h>
#include <errno.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <syslog.h>

#include "config.h"
#define STATIC_SUPER
#include "super.h"


/* ------------------------------------------------------------------------ */
int main(int argc, char **argv)
{
	signal(SIGPIPE, SIG_IGN);

	char const *action = NULL;
	char const *id = NULL;
	unsigned quiet = 0;

	unsigned i = 1;
	for (; (!action || !id) && i < argc; ++i) {
		char const *arg = argv[i];
		if (arg[0] == '-') {
			if (arg[1] == 'q' && !arg[2]) {
				quiet = 1;
				continue;
			}
			err(1, "error: invalid parameter '%s'", arg);
		}
		if (!action)
			action = arg;
		else
			id = arg;
	}

	char result[4096];
	ssize_t len = !action ?
				super("help", "", NULL, 0, result, sizeof(result)-1) :
				super(action, id ?: "", argv + i, argc - i, result, sizeof(result)-1);

	if (len < 0)
		err(-1, "socket %s", len == -1 ? SUPERD_SOCKET : "read");

	result[len] = 0;
	if (result[0] == '-') {
		if (!quiet)
			err(1, "failed: %s", result+1);
		else
			return 1;
	}

	if (result[0] == '!')
		return atoi(result+1);

	if (strcmp(result, "ok")) {
		if (!quiet)
			if (write(1, result, strlen(result)) < 0)
				perror("console write");
	}
	return 0;
}
