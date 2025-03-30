
/* ------------------------------------------------------------------------ */
static void sig_any(int signo)
{
	char const *signame = NULL;
	switch (signo) {
	case SIGHUP:  signame = "HUP";  break;
	case SIGPIPE: signame = "PIPE"; break;
	case SIGINT:  signame = "INT";  break;
	case SIGTERM: signame = "TERM"; break;
	default:
		warn("Recieved SIGNAL: %d", signo);
		return;
	}
	warn("SIG%s", signame);

	switch (signo) {
	case SIGTERM:
	case SIGINT:
		exit(-1);
	}
}

/* ------------------------------------------------------------------------ */
static int sigchild = 0;
static int sigalarm = 0;
static int sigbackup = 0;

/* ------------------------------------------------------------------------ */
static void sig_chld(int signo)
{	sigchild = 1; }
/* ------------------------------------------------------------------------ */
static void sig_alrm(int signo)
{	sigalarm = 1; }
/* ------------------------------------------------------------------------ */
static void sig_bckp(int signo)
{	sigbackup = 1; }

/* ------------------------------------------------------------------------ */
static void check_signals()
{
	if (sigchild) {
		sigchild = 0;
		sig_watch();
	}
	if (sigalarm) {
		sigalarm = 0;
		sig_sched();
	}
	if (sigbackup) {
		sigbackup = 0;
		sig_backup();
	}
}

/* ------------------------------------------------------------------------ */
static void init_signals()
{
	static const struct anysig {
		int sig;
		void (*fn)(int);
	} anysigs[] = {
		{ SIGHUP,  sig_any },
		{ SIGINT,  sig_any },
		{ SIGKILL, sig_any },
		{ SIGPIPE, sig_any },
		{ SIGPROF, sig_any },
		{ SIGTERM, sig_any },
		{ SIGUSR1, sig_any },
		{ SIGUSR2, sig_any }
	};
	const struct anysig *it = anysigs, *end = anysigs + countof(anysigs);
	do {
		signal(it->sig, it->fn);
	} while (++it < end);

	static const struct anysig interrupts[] = {
		{ SIGCHLD, sig_chld },
		{ SIGALRM, sig_alrm }
	};
	it = interrupts;
	end = interrupts + countof(interrupts);
	do {
		struct sigaction act;
		act.sa_flags = 0;
		sigemptyset(&act.sa_mask);
		act.sa_handler = it->fn;
		sigaction(it->sig, &act, NULL);
	} while (++it < end);
}
