#include <alef.h>
#include "hackers.h"


extern int	Pids[];
extern int	CurrentPid;
extern Lock	PidsLock;


void
Problem0(EventQueue *q)
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


