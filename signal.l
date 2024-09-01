#include <alef.h>
#include "hackers.h"


int
IgnoreSignal(int sig)
{
	Sigaction act;

	memset(&act, 0, sizeof act);
	act.handler = SIG_IGN;
	act.flags = SA_ONSTACK | SA_RESTART | SA_SIGINFO;

	return sigaction(sig, &act, nil);
}
