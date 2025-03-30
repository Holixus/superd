/* ------------------------------------------------------------------------ */
static long get_uptime()
{
	struct sysinfo info;
	sysinfo(&info);

	return info.uptime;
}

/* ------------------------------------------------------------------------ */
static char *time2str(char *out, size_t size, long time)
{
	static char const q[] = "dhms";
	long part[4];
	int i;

	part[3] = time % 60;          /* seconds */
	part[2] = (time /= 60) % 60;  /* minutes */
	part[1] = (time /= 60) % 24;  /* hours */
	part[0] = (time /= 24);       /* days */

	char *end = out + size;

	for (i = 0; i < 4; ++i) {
		if (part[i] || i == 3) {
			out += snprintf(out, (size_t)(end-out), "%li%c", part[i], q[i]);
			++i;
			if (i < 4 && part[i])
				out += snprintf(out, (size_t)(end-out), " %li%c", part[i], q[i]);
			break;
		}
	}
	return out;
}

