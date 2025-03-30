
queue_t s_sched;
queue_t s_watch;

static void sched_update();
static void sig_sched();

/* ------------------------------------------------------------------------ */
static int log_status(char const *id, pid_t pid, int status, int crash_only)
{
	if (!WIFSIGNALED(status)) {
		if (!crash_only)
			syslog(LOG_DEBUG, "process '%s'[%d] exited with code %d", id, pid, WEXITSTATUS(status));
		return 0;
	}

	char const *sig = NULL;
	switch (WTERMSIG(status)) {
	case SIGSEGV: sig = "SEGV"; break;
	case SIGABRT: sig = "ABRT"; break;
	case SIGILL:  sig = "ILL";  break;
	case SIGFPE:  sig = "FPE";  break;
	case SIGPIPE: sig = "PIPE"; break;
	}

	if (!sig) {
		if (WCOREDUMP(status)) {
			syslog(LOG_DEBUG, "process '%s'[%d] was crashed down by core dump", id, pid);
			return 1;
		}
		return 0;
	}

	syslog(LOG_DEBUG, "process '%s'[%d] was terminated by SIG%s", id, pid, sig);
	return 1;
}

/* ------------------------------------------------------------------------ */
static void sig_watch()
{
	pid_t pid;
	int status;
	while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
		proc_t *p = queue_get_by_pid(&s_watch, pid);
		if (p) {
			p->pid = 0;
			p->exit = WEXITSTATUS(status);
			long stop_time = get_uptime();
			if (stop_time - p->start_time >= 2)
				p->fast_restart = 1; /* fast_restart */
			else
				--(p->fast_restart);

			if (log_status(p->id, pid, status, 0)) {
				if (p->fast_restart < 0)
					p->next_start = get_uptime() + 1;
				else
					proc_start(p);
			} else {
				switch (p->todo) {
				case TODO_STOP:
					break;
				case TODO_RESTART:
					p->next_start = get_uptime() + p->delay;
					sched_update();
					break;
				default:
					proc_free(p);
				}
				p->todo = 0;
			}
			continue;
		}

		p = queue_get_by_pid(&s_sched, pid);
		if (p) {
			log_status(p->id, pid, status, 1);
			p->pid = 0;
			p->exit = WEXITSTATUS(status);
			if (p->sock) {
				char out[20];
				if (write(p->sock, out, (size_t)snprintf(out, sizeof(out), "!%d", p->exit) + 1) < 0)
					syslog(LOG_ERR, "write to superd socket failed: %m");
				close(p->sock);
				p->sock = 0;
			}
			if (!p->next_start) {
				switch (p->todo) {
				case TODO_STOP:
					break;
				case TODO_RESTART:
					p->next_start = get_uptime() + p->delay;
					sched_update();
					break;
				default:
					proc_free(p);
				}
				p->todo = 0;
			}
		} else
			log_status("UNREGISTERED", pid, status, 0);
	}
}

/* ------------------------------------------------------------------------ */
static long sched_get_wake_delay()
{
	long time = queue_get_next_start_time(&s_sched);
	long watch = queue_get_next_start_time(&s_watch);
	if (time < 0) {
		time = watch;
		watch = -1;
	}

	if (time < 0)
		return 0; /* for alarm stop */

	if (watch > 0 && watch < time)
		time = watch;

	long delay = time - get_uptime();
	if (!delay)
		delay = -1; /* for immediate scheduler start */
	return delay;
}

/* ------------------------------------------------------------------------ */
static void sched_queue(queue_t *q)
{
	long t;
	proc_t *p;
	while ( (p = queue_get_by_time(q, t = get_uptime())) ) {
		proc_start(p);
		if (p->period) {
			long d = 1 + (t - p->next_start) / p->period;
			p->next_start += d * p->period;
		} else {
			p->next_start = 0;
		}
	}
}

/* ------------------------------------------------------------------------ */
static void sched_update()
{
	long delay;
	while ( (delay = sched_get_wake_delay()) < 0 ) {
		sched_queue(&s_sched);
		sched_queue(&s_watch);
	}

	alarm((unsigned)delay); /* start/stop alarm timer */
}

/* ------------------------------------------------------------------------ */
static void sig_sched()
{
	sched_queue(&s_sched);
	sched_queue(&s_watch);
	sched_update();
}


/* ------------------------------------------------------------------------ */
static proc_t *queues_get_proc(char const *id)
{
	proc_t *p = queue_get_by_id(&s_sched, id);
	if (!p)
		p = queue_get_by_id(&s_watch, id);
	return p;
}

/* ------------------------------------------------------------------------ */
static char *rest_str(char const **src, char *str, size_t size)
{
	char const *in = *src;
	while (*in && --size)
		switch (*in) {
		case '\t':
			++in;
		case '\n':
			goto _finish;
		default:
			*str++ = *in++;
		}
_finish:
	*str = 0;
	*src = in;
	return str;
}

/* ------------------------------------------------------------------------ */
static long rest_long(char const **src)
{
	char buf[32], *str = buf;
	int size = sizeof(str);
	char const *in = *src;
	while (*in && --size)
		switch (*in) {
		case '\t':
			++in;
		case '\n':
			goto _finish;
		default:
			*str++ = *in++;
		}
_finish:
	*str = 0;
	*src = in;
	return atol(buf);
}

/* ------------------------------------<------------------------------------- */
static ssize_t safe_write(int fd, char const *data, size_t size)
{
	ssize_t ret;
	do {
		ret = write(fd, data, size);
	} while (ret < 0 && errno == EINTR);
	return ret;
}

/* ------------------------------------<------------------------------------- */
static ssize_t safe_read(int fd, char *data, size_t size)
{
	ssize_t ret;
	do {
		ret = read(fd, data, size);
	} while (ret < 0 && errno == EINTR);
	return ret;
}

/* ------------------------------------------------------------------------ */
static int queues_backup(char const *file_name)
{
	enum { length = 0x20000 };
	char *file = mmap(NULL, length, PROT_WRITE|PROT_READ, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	if (file == MAP_FAILED) {
		warn("can't mmap backup file: %m");
		return -1;
	}

	queue_t *queues[] = { &s_sched, &s_watch, NULL };
	queue_t **pos = queues, *q;
	char *out = file, *oend = file + length;
	while ((q = *pos++)) {
		if (q->count) {
			proc_t **it, **end = q->index + q->count;
			for (it = q->index; it < end; ++it) {
				proc_t *p = *it;
				out += snprintf(out, (size_t)(oend-out), "%s\t%d\t%d\t%ld",
						p->id, p->quiet, p->period,
						p->next_start ? p->next_start - get_uptime() : (p->pid?0:-1));
				int c = p->argc;
				char **a = p->argv;
				while (c--)
					out += snprintf(out, (size_t)(oend-out), "\t%s", *a++);

				*out++ = '\n';
			}
		}
		*out++ = '\n';
	}
	*out++ = 0;

	int fd = open(file_name, O_CREAT|O_TRUNC|O_WRONLY, 0666);
	if (fd < 0) {
		warn("can't backup queue (to %s): %m", file_name);
		return -1;
	}
	safe_write(fd, file, (size_t)(out - file));
	close(fd);
	munmap(file, length);
	return 0;
}

/* ------------------------------------------------------------------------ */
static void queues_restore(char const *file_name)
{
	int fd = open(file_name, O_RDONLY);
	if (fd < 0)
		return;

	enum { length = 0x20000 };
	char *file = mmap(NULL, length, PROT_WRITE|PROT_READ, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	if (file == MAP_FAILED) {
		warn("can't mmap backup file: %m");
		return;
	}

	ssize_t rdn = safe_read(fd, file, length);
	close(fd);
	if (rdn < 0)
		goto _error;

	file[rdn] = 0;
	char const *in = file;

	queue_t *queues[] = { &s_sched, &s_watch, NULL };
	queue_t **pos = queues, *q;
	while ((q = *pos++)) {
		while (*in && *in != '\n') {
			proc_t *p;
			char id[sizeof(p->id)];
			rest_str(&in, id, sizeof(id));

			p = queue_new(q, id);
			p->quiet = (int)rest_long(&in);
			p->period = (int)rest_long(&in);
			long delay = rest_long(&in);
			p->next_start = delay < 0 ? 0 : get_uptime() + delay;
			p->argc = 0;
			p->pid = 0;
			p->start_time = 0;
			p->exit = 0;
			p->sock = 0;
			p->fast_restart = 1;
			p->todo = 0;

			char *out_cmd = p->cmd_line, *out_end = p->cmd_line + sizeof(p->cmd_line);
			while (*in && *in != '\n') {
				p->argv[p->argc] = out_cmd;
				out_cmd = 1 + rest_str(&in, out_cmd, (size_t)(out_end - out_cmd));
				++(p->argc);
			}
			if (*in != '\n')
				break;
			++in;
		}
		if (*in)
			++in;
	}

_error:
	munmap(file, length);
	sched_update();
}

/* ------------------------------------------------------------------------ */
static void sig_backup()
{
	queues_backup(BACKUP_FILENAME);
}
