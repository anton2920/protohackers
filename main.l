#include <alef.h>
#include "hackers.h"

#define NWORKERS	5


void
ServerWorker(EventQueue *q)
{
	byte buffer[1024];

	while (1) {
		Event events[64];
		int	nbytes;
		int	i, n;

		n = q->GetEvents(events, ArrayLength(events));
		if (n < 0) {
			/* TODO(anton2920): break only on EINVAl. */
			break;
		}

		for (i = 0; i < n; ++i) {
			Event * event;
			event = &events[i];

			if (event->Flags & EV_EOF) {
				continue;
			}

			switch (event->Type) {
			case EventRead:
				nbytes = read(event->Identifier, buffer, sizeof buffer);
				if (nbytes < 0) {
					Errorf("Failed to read from client: %r");
					continue;
				}

				nbytes = write(event->Identifier, buffer, nbytes);
				if (nbytes < 0) {
					Warnf("Failed to write to client: %r");
				}
				break;
			}
		}
	}
}


void
main()
{
	EventQueue qs[NWORKERS], q;
	int	i, l, ret, quit;

	// SetLevel(LevelDebug);
	fmtinstall('A', Addrconv);

	l = TCPListen(INADDR_ANY, 12345, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:12345...");

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

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc ServerWorker(&qs[i]);
	}

	quit = 0;
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

			Debugf("Got event %d", event->Type);

			switch (event->Type) {
			case EventRead:
				addrlen = sizeof addr;
				c = _accept(l, (Sockaddr * ) & addr, &addrlen);
				if (c < 0) {
					Errorf("Failed to accept incoming connection: %r");
					continue;
				}

				Infof("Accepted from %A:%d", addr.addr, addr.port);

				close(c);
				break;
			case EventSignal:
				Infof("Received signal %d, exitting...", event->Identifier);
				quit = 1;
				break;
			}
		}
	}
}


