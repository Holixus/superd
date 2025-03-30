struct l_queue;

typedef
struct _proc {
	char id[32];

	int quiet;          /* execute the command 'silently' */
	int period;         /* seconds */
	int delay;          /* delay before start after stop */

	long next_start;    /* next system uptime for start process */

	int todo;           /* what to do then process is exited */
	pid_t pid;          /* started process id (for watching/killing) */
	long start_time;    /* when started */
	int fast_restart;

	int exit;           /* exit code */
	int sock;           /* dup of connsock for postponed answer */

	char cmd_line[388]; /* 512 - 124 */
	char *argv[64];
	int argc;

	struct l_queue *queue;
} proc_t;

/* ------------------------------------------------------------------------ */
static void store_str(char *out, char const *str)
{
	while (*str) {
		if (*str == ':' || *str == '\\')
			*out++ = '\\';
		*out++ = *str++;
	}
}

enum {
	PROC_QUEUE_LENGTH = 32,
	TODO_STOP = 1,
	TODO_RESTART = 2
};

typedef
struct l_queue {
	proc_t *index[PROC_QUEUE_LENGTH];
	int count;
} queue_t;


static proc_t s_heap[PROC_QUEUE_LENGTH];

/* ------------------------------------------------------------------------ */
static void sig_bckp(int signo);

/* ------------------------------------------------------------------------ */
static proc_t *queue_get_by_idx(queue_t *q, int idx)
{
	return idx < q->count ? q->index[idx] : NULL;
}

/* ------------------------------------------------------------------------ */
static proc_t *queue_get_by_pid(queue_t *q, int pid)
{
	proc_t **it = q->index,
	       **end = it + q->count;

	while (it < end)
		if (it[0]->pid == pid)
			return *it;
		else
			++it;

	return NULL;
}

/* ------------------------------------------------------------------------ */
static proc_t *queue_get_by_id(queue_t *q, char const *id)
{
	proc_t **it = q->index,
	       **end = it + q->count;

	while (it < end)
		if (!strcmp(it[0]->id, id))
			return *it;
		else
			++it;

	return NULL;
}

/* ------------------------------------------------------------------------ */
static proc_t *queue_get_by_time(queue_t *q, long time)
{
	proc_t **it, **end = q->index + q->count;
	for (it = q->index; it < end; ++it) {
		long ns = it[0]->next_start;
		if (ns && ns <= time)
			return *it;
	}

	return NULL;
}

/* ------------------------------------------------------------------------ */
static long queue_get_next_start_time(queue_t *q)
{
	if (!q->count)
		return -1;

	proc_t **it, **end = q->index + q->count;
	long min = 0;
	for (it = q->index; it < end; ++it) {
		long ns = it[0]->next_start;
		if (ns && (ns < min || !min))
			min = ns;
	}

	return min ?: -1;
}

/* ------------------------------------------------------------------------ */
static void safe_strncpy(char *dst, char const *src, size_t size)
{
	strncpy(dst, src, size-1);
	dst[size-1] = 0;
}

/* ------------------------------------------------------------------------ */
static proc_t *queue_new(queue_t *q, char const *id)
{
	proc_t *it = s_heap,
	       *end = it + countof(s_heap);

	while (it < end)
		if (!it->id[0]) {
			safe_strncpy(it->id, id, sizeof(it->id));
			q->index[q->count++] = it;
			it->queue = q;
			it->pid = 0;
			it->exit = 0;
			sig_bckp(0);
			return it;
		} else
			++it;

	return NULL;
}

/* ------------------------------------------------------------------------ */
static void proc_free(proc_t *p)
{
	if (p) {
		p->id[0] = 0;
		p->pid = 0;
		queue_t *q = p->queue;
		if (!q)
			return;
		p->queue = NULL;
		proc_t **it = q->index,
		       **end = it + q->count;
		while (it < end)
			if (*it == p) {
				long tail = q->count - (it-q->index) - 1;
				if (tail)
					memmove(it, it+1, (size_t)tail*sizeof(*it));
				q->index[--(q->count)] = NULL;
				break;
			} else
				++it;
		sig_bckp(0);
	}
}

/* ------------------------------------------------------------------------ */
static void proc_remove(proc_t *p)
{
	if (p->pid)
		kill(p->pid, SIGTERM);
	proc_free(p);
}

/* ------------------------------------------------------------------------ */
static int proc_kill(proc_t *p)
{
	return (p->pid) ? kill(p->pid, SIGTERM) : 0;
}

/* ------------------------------------------------------------------------ */
static char *proc_get_cmd(proc_t *p, char *cmd, size_t size)
{
	int i;
	char *end = cmd + size;
	cmd = stpncpy(cmd, p->argv[0], size);

	for (i = 1; i < p->argc; ++i)
		cmd += snprintf(cmd, (size_t)(end-cmd), " %s", p->argv[i]);
	return cmd;
}

/* ------------------------------------------------------------------------ */
static int proc_set_cmd(proc_t *p, char **argv, int argc)
{
	int i;
	char *cmd = p->cmd_line,
	     *end = p->cmd_line + sizeof(p->cmd_line) - 1;
	if (argc > countof(p->argv)-1) {
		argc = countof(p->argv)-1;
		syslog(LOG_DEBUG, "too many arguments for queue item '%s'", p->id);
	}
	p->argc = argc;
	for (i = 0; i < argc; ++i) {
		p->argv[i] = cmd;
		cmd = stpncpy(cmd, argv[i], (size_t)(end-cmd));
		if (cmd < end)
			++cmd;
	}
	p->argv[i] = NULL;
	*cmd = 0;
	return 1;
}

/* ------------------------------------------------------------------------ */
static int proc_start(proc_t *p)
{
	pid_t pid = fork();
	if (!pid) {
		int fd = 32;//dup(0);
		while (fd > 2)
			close(fd--);
		if (p->quiet) {
			int nd = open("/dev/null", O_RDWR);
			dup2(nd, 0);
			dup2(nd, 1);
			dup2(nd, 2);
			close(nd);
		}
		execvp(p->argv[0], p->argv);
		char cmd[1000];
		proc_get_cmd(p, cmd, sizeof(cmd));
		openlog(LOG_NAME, LOG_PID|LOG_PERROR, LOG_DAEMON);
		syslog(LOG_ERR, "[%s] failed execv '%s': %m", p->id, cmd);
		closelog();
		exit(-1);
	}
	if (pid < 0) {
		syslog(LOG_ERR, "[%s] fork fail: %m", p->id);
		return -1;
	}
	p->pid = pid;
	p->start_time = get_uptime();
	syslog(LOG_DEBUG, "[%s] spawned", p->id);
	return 0;
}

