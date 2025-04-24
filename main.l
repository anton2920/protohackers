#include <alef.h>
#include "hackers.h"

#define NWORKERS	1

int	Pids[NWORKERS];
int	CurrentPid;
Lock	PidsLock;


void Problem0(EventQueue*);
void Problem1(EventQueue*);
void Problem2(EventQueue*);

void
main()
{
	EventQueue qs[NWORKERS], q;
	int	i, l, ret, quit, rr;
	ClientData2 data;

	SetLevel(LevelDebug);
	fmtinstall('A', Addrconv);
	fmtinstall('E', Eventconv);
	fmtinstall('J', Jsonconv);

	l = TCPListen(INADDR_ANY, 12345, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:12345...");

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc Problem2(&qs[i]);
	}

	ret = q.Init();
	check ret >= 0, "failed to initialize event queue";

	ret = q.AddSocket(l, RequestRead, TriggerEdge, nil);
	check ret >= 0, "failed to add socket to event queue";

	ret = IgnoreSignal(SIGTERM);
	check ret >= 0, "failed to ignore SIGTERM";

	ret = q.AddSignal(SIGTERM);
	check ret >= 0, "failed to add SIGTERM";

	ret = IgnoreSignal(SIGINT);
	check ret >= 0, "failed to ignore SIGINT";

	ret = q.AddSignal(SIGINT);
	check ret >= 0, "failed to add SIGINT";

	quit = 0;
	rr = 0;
	while (!quit) {
		SockaddrIn addr;
		Event events[64];
		Circular * buffer;
		uint addrlen;
		int	c, n;

		n = q.GetEvents(events, ArrayLength(events));
		if (n < 0) {
			Errorf("Failed to get events from queue: %r");
			continue;
		}

		for (i = 0; i < n; ++i) {
			Event * event;
			event = &events[i];

			Debugf("[ main ]: Got event %E", event);

			switch (event->Type) {
			case EventRead:
				addrlen = sizeof addr;
				c = _accept(l, (Sockaddr * ) & addr, &addrlen);
				if (c < 0) {
					Errorf("Failed to accept incoming connection: %r");
					continue;
				}

				Debugf("Accepted from %A:%d", addr.addr, addr.port);

				InitClientData2(&data);

				qs[rr++].AddSocket(c, RequestRead, TriggerEdge, &data);
				rr %= NWORKERS;
				break;
			case EventSignal:
				Infof("Received signal %d, exitting...", event->Identifier);
				quit = 1;
				break;
			}
		}
	}

	PidsLock.lock();
	for (i = 0; i < NWORKERS; ++i) {
		kill(Pids[i], SIGTERM);
	}
	PidsLock.unlock();
}


