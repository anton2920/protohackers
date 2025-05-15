#include <alef.h>
#include "hackers.h"


intern
void
worker(EventQueue *q)
{
	byte buffer[1024];

	ProcInit();

	while (1) {
		Event events[64];
		int	bytesRead;
		int	i, n;

		n = q->GetEvents(events, ArrayLength(events));
		if (n < 0) {
			/* TODO(anton2920): break only on EINVAl. */
			break;
		}

		for (i = 0; i < n; ++i) {
			Event * event;
			event = &events[i];

			Debugf("[worker]: Got event %E", event);

			if (event->Data[0] > 0) {
				bytesRead = 0;

				switch (event->Type) {
				case EventRead:
					while (bytesRead < event->Data[0]) {
						int	nbytes;

						nbytes = read(event->Identifier, buffer, sizeof buffer);
						if (nbytes < 0) {
							Errorf("Failed to read from client: %r");
							continue 2;
						}
						bytesRead += nbytes;

						nbytes = write(event->Identifier, buffer, nbytes);
						if (nbytes < 0) {
							Warnf("Failed to write to client: %r");
						}
					}
					break;
				}
			}

			if (event->EndOfFile()) {
				close(event->Identifier);
				continue;
			}
		}
	}
}


void
Problem0(sint port)
{
	EventQueue qs[NWORKERS], q;
	int	i, l, ret, rr;

	ProcInit();

	l = TCPListen(INADDR_ANY, port, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:%d...", port);

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc worker(&qs[i]);
	}

	ret = q.Init();
	check ret >= 0, "failed to initialize event queue";

	ret = q.AddSocket(l, RequestRead, TriggerEdge, nil);
	check ret >= 0, "failed to add socket to event queue";

	rr = 0;
	while (1) {
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

			addrlen = sizeof addr;
			c = _accept(l, (Sockaddr * ) & addr, &addrlen);
			if (c < 0) {
				Errorf("Failed to accept incoming connection: %r");
				continue;
			}

			Debugf("Accepted from %A:%d", addr.addr, addr.port);

			qs[rr++].AddSocket(c, RequestRead, TriggerEdge, nil);
			rr %= NWORKERS;
		}
	}
}


