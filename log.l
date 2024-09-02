#include <alef.h>
#include "hackers.h"


byte *Level2String[] =
{
	[LevelDebug] "DEBUG",
	[LevelInfo] "INFO",
	[LevelWarn] "WARN",
	[LevelError] "ERROR",
	[LevelFatal] "FATAL",
};


intern Level LogLevel = LevelInfo;
intern Lock LogLock;


void
Logf(Level level, byte *format, void *argp)
{
	byte buffer[1024];
	byte date[100];
	byte * end;
	Tm * tm;
	int	len;

	LogLock.lock();
	if ((level < LogLevel) && (level < LevelFatal)) {
		LogLock.unlock();
		return;
	}

	tm = localtime(time(nil));
	snprint(date, sizeof date, "%d/%.2d/%.2d %.2d:%.2d:%.2d", tm->year + 1900, tm->mon + 1, tm->mday, tm->hour, tm->min, tm->sec);
	LogLock.unlock();

	end = doprint(buffer, buffer + sizeof(buffer), format, argp);
	len = end - buffer;
	if (buffer[len-1] != '\n') {
		buffer[len] = '\n';
		buffer[len+1] = '\0';
	}

	switch (level) {
	case LevelFatal:
		fprint(2, "%s %5s %s", date, Level2String[level], buffer);
		exits("fatal error");
		break;
	default:
		fprint(2, "%s %5s %s", date, Level2String[level], buffer);
		break;
	}
}


void
Debugf(byte *format, ...)
{
	Logf(LevelDebug, format, ...);
}


void
Infof(byte *format, ...)
{
	Logf(LevelInfo, format, ...);
}


void
Warnf(byte *format, ...)
{
	Logf(LevelWarn, format, ...);
}


void
Errorf(byte *format, ...)
{
	Logf(LevelError, format, ...);
}


void
Fatalf(byte *format, ...)
{
	Logf(LevelFatal, format, ...);
}


Level
SetLevel(Level level)
{
	Level old;

	LogLock.lock();
	old = LogLevel;
	LogLevel = level;
	LogLock.unlock();

	return old;
}


