#ifndef HAVE_SD_H

#ifndef LAUNCH_SOCKET
# define LAUNCH_SOCKET "/tmp/dfdf"
#endif

#ifndef countof
# define countof(name) (sizeof(name)/sizeof(name[0]))
#endif

#ifdef HOST_DEBUG
static void _trace(char const *fmt, ...)
{
	char buf[512];
	va_list va;
	va_start(va, fmt);
	int count = vsnprintf(buf, sizeof(buf), fmt, va);
	va_end(va);
	(void)write(1, buf, count);
}
#else
static inline void _trace(char const *fmt, ...) { }
#endif


#if defined(DEFINE_SUPER) || defined(STATIC_SUPER)

#ifdef STATIC_SUPER
static
#endif

ssize_t super(char const *cmd, char const *id, char **argv, int argc, char *result, size_t maxsize)
{
	char seq[4096], *out = seq;
	*out++ = (char)(argc + 2);
	out = stpcpy(out, cmd) + 1;
	out = stpcpy(out, id) + 1;
	while (argc-- > 0) {
		size_t len = strlen(*argv)+1;
		memcpy(out, *argv++, len);
		out += len;
	}

	struct sockaddr_un addr;
	int sock = socket(AF_LOCAL, SOCK_STREAM, 0);

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_LOCAL;
	strcpy(addr.sun_path, SUPERD_SOCKET);

	int try = 5;
	do {
		if (!connect(sock, (struct sockaddr *)&addr, sizeof(addr)))
			break;
		if (errno != ECONNREFUSED && errno != EINTR)
			goto _fail;
		usleep(10000);
	} while (--try);

	if (!try) {
_fail:;
		int e = errno;
		close(sock);
		errno = e;
		return -1;
	}

	if (write(sock, seq, (size_t)(out - seq)) < 0)
		goto _fail;

	ssize_t length;
	if ((length = read(sock, result, maxsize)) >= 0) {
		close(sock);
		return length;
	}
	close(sock);
	return -2;
}

#else

int super(char const *cmd, int len, char *result, int maxsize);

#endif
#endif
