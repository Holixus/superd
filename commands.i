typedef
struct out {
	int sock;
	char buf[8192];
	int len;
} output_t;

/* ------------------------------------------------------------------------ */
static char *gen_id()
{
	static char id[16];
	snprintf(id, sizeof(id), "#%lX%X", get_uptime(), rand());
	return id;
}

/* ------------------------------------------------------------------------ */
typedef
struct cmd_opts {
	int delay,
	    period,
	    wait,
	    quiet,
	    leave;
} cmd_opts_t;

/* ------------------------------------------------------------------------ */
static int cmd_parse_opts(cmd_opts_t *opts, char **argv, int argc)
{
	opts->delay = opts->period = opts->wait = opts->quiet = opts->leave = 0;
	char **cur_arg = argv;
	char **end_arg = argv + argc;

	while (cur_arg < end_arg && (*cur_arg)[0] == '-') {
		switch ((*cur_arg)[1]) {
		case 'q':
			opts->quiet = 1;
			++cur_arg;
			break;
		case 'l':
			opts->leave = 1;
			++cur_arg;
			break;
		case 'w':
			opts->wait = 1;
			++cur_arg;
			break;
		case 'd':
			if (++cur_arg >= end_arg)
				return -1;
			opts->delay = atoi(*cur_arg++);
			break;
		case 'p':
			if (++cur_arg >= end_arg)
				return -1;
			opts->period = atoi(*cur_arg++);
			break;
		default:
			return -1;
		}
	}
	return (int)(cur_arg - argv); /* number of eaten args */
}

/* ------------------------------------------------------------------------ */
static int cmd_free_proc(char const *id, int leave)
{
	proc_t *p = queues_get_proc(id);
	if (p) {
		if (p->pid) {
			p->next_start = 0;

			if (p->id[0] != '.') {
				char _id[sizeof(p->id)+10];
				snprintf(_id, sizeof(_id), ".%s.%x", p->id, p->pid);
				safe_strncpy(p->id, _id, sizeof(p->id));
			}

			if (!leave) {
				_trace("kill[%d]\n", p->pid);
				kill(p->pid, p->id[0] != '.' ? SIGTERM : SIGKILL);
			}
		} else {
			proc_free(p);
		}
		return 0;
	}
	return -1;
}

/* ------------------------------------------------------------------------ */
static char const *cmd_sched(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (!argc || args < 0)
		return "?";

	char **cur_arg = argv;
	char **end_arg = argv + argc;

	if (!*id)
		id = gen_id();

	cmd_free_proc(id, opts.leave);
	proc_t *p = queue_new(&s_sched, id);
	if (!p) {
		return "-queue overflow";
	}
	p->period = opts.period;
	p->delay = opts.delay;
	p->quiet = opts.quiet;
	p->next_start = get_uptime() + opts.delay;
	p->pid = 0;
	if (opts.wait) {
		p->sock = dup(result->sock);
		result->len = -1;
	}
	proc_set_cmd(p, cur_arg, (int)(end_arg - cur_arg));
	sched_update();
	return (opts.wait) ? result->buf : "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_watch(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (!argc || args < 0)
		return "?";

	char **cur_arg = argv;
	char **end_arg = argv + argc;

	if (!*id)
		id = gen_id();

	cmd_free_proc(id, opts.leave);
	proc_t *p = queue_new(&s_watch, id);
	if (!p) {
		return "-queue overflow";
	}
	p->period = 0;
	p->delay = opts.delay;
	p->quiet = opts.quiet;
	p->fast_restart = 1;
	p->pid = 0;
	p->next_start = get_uptime() + opts.delay;
	proc_set_cmd(p, cur_arg, (int)(end_arg - cur_arg));
	sched_update();
	return "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_set(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (args < 0)
		return "?";

	proc_t *p = queue_get_by_id(&s_sched, id);
	if (!p)
		p = queue_get_by_id(&s_watch, id);
	if (!p)
		return "-no id";

	p->period = opts.period;
	p->delay = opts.delay;
	p->quiet = opts.quiet;
	p->next_start = get_uptime() + opts.delay;
	sched_update();
	sig_bckp(0);
	return "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_list(output_t *result, char const *id, char **argv, int argc)
{
	static const char sched_fmt[] = "%s%-16s %-6s %-9s %-9s %-6s %s\n";
	static const char *sched_hdr[] = { "Scheduler list:\n", "id", "pid", "delay", "period", "opts", "command" };
	static const char watch_fmt[] = "%s%-16s %-6s %-9s %-6s %s\n";
	static const char *watch_hdr[] = { "\nWatch list:\n", "id", "pid", "delay", "opts", "command" };

	char cmd[512];
	char start_time[20], period[20], pid[12], opts[12];
	char *out = result->buf, *end = result->buf + sizeof(result->buf);
	int i;
	proc_t *p;

	out += snprintf(out, (size_t)(end-out), sched_fmt, sched_hdr[0], sched_hdr[1], sched_hdr[2], sched_hdr[3], sched_hdr[4], sched_hdr[5], sched_hdr[6]);
	for (i = 0; (p = queue_get_by_idx(&s_sched, i)); ++i) {
		proc_get_cmd(p, cmd, sizeof(cmd));

		if (p->pid)
			snprintf(pid, sizeof(pid), "%d", p->pid);
		else
			snprintf(pid, sizeof(pid), "-/%d", p->exit);

		if (p->next_start)
			time2str(start_time, sizeof(start_time), p->next_start - get_uptime());
		else
			start_time[0] = '-', start_time[1] = 0;

		time2str(period, sizeof(period), p->period);
		snprintf(opts, sizeof(opts), "%s", p->quiet?"q":"-");
		out += snprintf(out, (size_t)(end-out), sched_fmt, "", p->id, pid, start_time, period, opts, cmd);
	}

	out += snprintf(out, (size_t)(end-out), watch_fmt, watch_hdr[0], watch_hdr[1], watch_hdr[2], watch_hdr[3], watch_hdr[4], watch_hdr[5]);
	for (i = 0; (p = queue_get_by_idx(&s_watch, i)); ++i) {
		proc_get_cmd(p, cmd, sizeof(cmd));
		if (p->pid)
			snprintf(pid, sizeof(pid), "%d", p->pid);
		else
			snprintf(pid, sizeof(pid), "-/%d", p->exit);

		if (p->next_start)
			time2str(start_time, sizeof(start_time), p->next_start - get_uptime());
		else
			start_time[0] = '-', start_time[1] = 0;
		snprintf(opts, sizeof(opts), "%s", p->quiet?"q":"-");
		out += snprintf(out, (size_t)(end-out), watch_fmt, "", p->id, pid, start_time, opts, cmd);
	}

	//_trace("cmd: list %s\n", id);
	result->len = (int)(out - result->buf);
	return result->buf;
}

/* ------------------------------------------------------------------------ */
static char const *cmd_remove(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (args < 0)
		return "?";

	if (cmd_free_proc(id, opts.leave) < 0)
		return "-no id";

	sched_update();
	queues_backup(BACKUP_FILENAME);
	return "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_stop(output_t *result, char const *id, char **argv, int argc)
{
	proc_t *p = queues_get_proc(id);
	if (!p)
		return "-no id";

	if (!p->pid && !p->next_start)
		return "-not started";

	p->todo = TODO_STOP;
	p->next_start = 0;

	if (p->pid)
		if (kill(p->pid, SIGTERM) < 0) {
			char const *t = "-?";
			switch (errno) {
			case EPERM:  t = "-no permission"; break;
			case ESRCH:  t = "-no process"; break;
			}
			return t;
		}
	sig_bckp(0);
	return "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_start(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (args < 0)
		return "?";

	proc_t *p = queues_get_proc(id);
	if (!p)
		return "-no id";

	if (p->pid)
		return "-started already";

	p->next_start = get_uptime() + opts.delay;
	sched_update();
	sig_bckp(0);
	return "ok";
}

/* ------------------------------------------------------------------------ */
static char const *cmd_restart(output_t *result, char const *id, char **argv, int argc)
{
	cmd_opts_t opts;
	int args = cmd_parse_opts(&opts, argv, argc);
	argc -= args;
	argv += args;

	if (args < 0)
		return "?";

	proc_t *p = queues_get_proc(id);
	if (!p)
		return "-no id";

	if (!p->pid && !p->next_start)
		return "-not started";

	if (p->pid) {
		p->next_start = 0;
		p->todo = TODO_RESTART;
		p->delay = opts.delay; /* delay for restart */
		if (kill(p->pid, SIGTERM) < 0) {
			char const *t = "-?";
			switch (errno) {
			case EPERM:  t = "-no permission"; break;
			case ESRCH:  t = "-no process"; break;
			}
			return t;
		}
	} else
		p->next_start = get_uptime() + opts.delay;

	sched_update();
	return "ok";
}

/* ------------------------------------------------------------------------ */
typedef
char const *(cmd_fn_t)(output_t *result, char const *id, char **argv, int argc);

struct act_cmd {
	char const *name;
	cmd_fn_t *fn;
	char const *usage;
};

/* ------------------------------------------------------------------------ */
static char const *usage[] = { "super'd  1.0  Copyright (c) 2018 Holixus\n\
usage:\n\
# super <action> <id> [-w] [-d <delay>] [-p <period>] <command-line>\n\
actions:\n",
"options:\n\
  -q           -- redirect all output to /dev/null\n\
  -l           -- leave the old queued item to die by it self\n\
  -w           -- wait for exit\n\
  -d <delay>   -- start delay (in seconds)\n\
  -p <period>  -- run program periodicaly (in seconds)\n" };

typedef
struct cmd {
	char buf[1024];
	char *argv[64];
	int argc;
} cmd_t;

/* ------------------------------------------------------------------------ */
static ssize_t answer(int sock, char const *buf, size_t size)
{
	ssize_t r = size > 0 ? write(sock, buf, size) : 0;
	int e = errno;
	close(sock);
	errno = e;
	return r;
}

/* ------------------------------------------------------------------------ */
static ssize_t exec_command(int sock, cmd_t *cmd)
{
	static struct act_cmd const acts[] = {
		{ "sched",  cmd_sched,  "<id> [-l] [-q] [-w] [-d <delay>] [-p <period>] <command-line>\n\t-- schedule the program to run once or periodicaly" },
		{ "watch",  cmd_watch,  "<id> [-l] [-q] [-d <delay>] <command-line>\n\t-- watch for the program for crash and restart it" },

		{ "set",    cmd_set,    "<id> [-q] [-d <delay>] [-p <period>]\n\t-- change options of a queued program" },

		{ "stop",   cmd_stop,   "<id>\n\t-- stop a queued program" },
		{ "start",  cmd_start,  "<id> [-d <delay>]\n\t-- start a queued program" },
		{ "restart",cmd_restart,"<id> [-d <delay>]\n\t-- stop and start a queued program" },

		{ "list",   cmd_list,   "\n\t-- list current queue" },
		{ "remove", cmd_remove, "<id> [-l]\n\t-- stop and remove a queued item" }
	};

	char **cur_arg = cmd->argv;
	char **end_arg = cmd->argv + cmd->argc;
	struct act_cmd const *cur = acts, *end = acts + countof(acts);

	if (!cmd->argc) {
_help:;
		char help[4096], *to = help, *tend = help+sizeof(help)-1;
		to += snprintf(to, (size_t)(tend - to), "%s", usage[0]);
		cur = acts;
		end = acts + countof(acts);
		while (cur < end) {
			to += snprintf(to, (size_t)(tend - to), "  %s %s\n", cur->name, cur->usage);
			++cur;
		}
		to += snprintf(to, (size_t)(tend - to), "%s", usage[1]);

		return answer(sock, help, (size_t)(to - help + 1));
	}

	cmd_fn_t *fn = NULL;
	while (cur < end) {
		if (!strcmp(cur->name, *cur_arg)) {
			fn = cur->fn;
			break;
		}
		++cur;
	}

	if (!fn)
		goto _help;

	output_t result;
	char const *ret;
	result.sock = sock;
	if (++cur_arg < end_arg) {
		char const *id = *cur_arg;
		while (*id && (isalnum(*id) || *id == '_' || *id == '-'))
			++id;
		ret = fn(&result, !*id ? *cur_arg : "", cur_arg + 1, (int)(end_arg - cur_arg - 1));
	} else {
		ret = fn(&result, "", cur_arg, (int)(end_arg - cur_arg));
	}

	if (ret[0] == '?')
		goto _help;

	return answer(sock, ret, ret == result.buf ? (size_t)(result.len + 1) : strlen(ret));
}
