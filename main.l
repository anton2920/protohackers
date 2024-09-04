#include <alef.h>
#include "hackers.h"

#define NWORKERS	5

int	Pids[NWORKERS];
int	CurrentPid;
Lock	PidsLock;


void Problem0(EventQueue*);
void Problem1(EventQueue*);


#if 1
void
main()
{
	byte * jsonString;
	int	consumed;
	Json json;

	SetLevel(LevelDebug);
	fmtinstall('J', Jsonconv);

	jsonString = "{ \"accounting\" : [	{ \"firstName\" : \"John\", \"lastName\"  : \"Doe\", \"age\"       : 23 }, { \"firstName\" : \"Mary\", \"lastName\"  : \"Smith\", \"age\"      : 32 }], \"sales\"      : [ { \"firstName\" : \"Sally\", \"lastName\"  : \"Green\", \"age\"      : 27 }, { \"firstName\" : \"Jim\", \"lastName\"  : \"Galley\", \"age\"       : 41 } ] }";

	consumed = ParseJson(jsonString, strlen(jsonString), &json);
	if (consumed < 0) {
		Errorf("Failed to parse JSON: %r\n");
		return;
	}
	print("%J\n", json);
}


#else
void
main()
{
	EventQueue qs[NWORKERS], q;
	int	i, l, ret, quit, rr;

	// SetLevel(LevelDebug);
	fmtinstall('A', Addrconv);
	fmtinstall('E', Eventconv);
	fmtinstall('J', Jsonconv);

	l = TCPListen(INADDR_ANY, 12345, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:12345...");

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc Problem1(&qs[i]);
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

				qs[rr++].AddSocket(c, RequestRead, TriggerEdge, nil);
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


#endif

