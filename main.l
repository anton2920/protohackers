#include <alef.h>
#include "hackers.h"

int	Pids[NWORKERS+1];
int	CurrentPid;
Lock	PidsLock;

void Problem0(sint);
void Problem1(sint);
void Problem2(sint);

void
ProcInit()
{
	PidsLock.lock();
	Pids[CurrentPid++] = getpid();
	PidsLock.unlock();
}


void
main()
{
	EventQueue q;
	int	quit, ret;
	int	i;

	SetLevel(LevelDebug);
	fmtinstall('A', Addrconv);
	fmtinstall('E', Eventconv);
	fmtinstall('J', Jsonconv);

	proc Problem0(12340);
	proc Problem1(12341);
	proc Problem2(12342);

	ret = q.Init();
	check ret >= 0, "failed to initialize event queue";

	ret = IgnoreSignal(SIGTERM);
	check ret >= 0, "failed to ignore SIGTERM";

	ret = q.AddSignal(SIGTERM);
	check ret >= 0, "failed to add SIGTERM";

	ret = IgnoreSignal(SIGINT);
	check ret >= 0, "failed to ignore SIGINT";

	ret = q.AddSignal(SIGINT);
	check ret >= 0, "failed to add SIGINT";

	quit = 0;
	while (!quit) {
		Event event;
		int	n;

		n = q.GetEvents(&event, 1);
		if (n < 0) {
			Errorf("Failed to get events from queue: %r");
			continue;
		}

		Infof("Received signal %d, exitting...", event.Identifier);
		quit = 1;
	}

	PidsLock.lock();
	for (i = 0; i < NWORKERS; ++i) {
		kill(Pids[i], SIGTERM);
	}
	PidsLock.unlock();
}


