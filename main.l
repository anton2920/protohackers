#include <alef.h>
#include "hackers.h"

#define NWORKERS	5

intern int	Pids[NWORKERS];
intern int	CurrentPid;
intern Lock	PidsLock;


void
ServerWorker(EventQueue *q)
{
	byte buffer[1024];

	PidsLock.lock();
	Pids[CurrentPid++] = getpid();
	PidsLock.unlock();

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
main()
{
	EventQueue qs[NWORKERS], q;
	int	i, l, ret, quit, rr;

	// SetLevel(LevelDebug);
	fmtinstall('A', Addrconv);
	fmtinstall('E', Eventconv);

	l = TCPListen(INADDR_ANY, 12345, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:12345...");

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc ServerWorker(&qs[i]);
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


